--!strict
--[[
	TankWorldController — садок в мире (Этап 3, только этот клиент): рыбы в витринах дворов баз,
	надписи над витринами и над большим аквариумом, слово садка над ведром у места рыбалки, всплески
	и искры событий витрин, слово «РЫНОК +50%!» над рынком острова. Числа — TankConfig.Display /
	Pier (ниже — их имена без «TankConfig.»), тексты — TankConfig.Texts, данные — атрибуты витрин,
	садка и игрока (RemoteNames, «Состояние садка и денег»; договор записи —
	tools/builder/DESIGN.md, «Tank slots at runtime»). Новых деталей на сервере нет: рыбы —
	клиентские копии (MapConfig.PartBudget.RuntimeReserve.TankFish), всё своё — в папке
	Workspace.TankWorld (одна невидимая деталь-держатель Anchor в начале координат, на ней
	Attachment'ы надписей и эффектов; рыбы — модели "DisplayFish_<база>_<витрина>"). Из чего
	сделаны рыба, надписи и эффекты — помощник TankDisplay.

	Что делает:
	  • Расстояние с запасом: цепочка task.delay раз в Display.CheckEvery секунд (без соединения)
	    меряет от камеры и от своего персонажа (ближнее из двух: в Studio камера всегда рядом с
	    ним, а в эмуляторе тестов камера стоит, где её поставили); базы, чей Tank.Glass ближе
	    Display.Range, «строятся» (у каждой свой Trove: соединения витрин, надпись садка), дальше
	    DropRange — убираются. Новая база читает все витрины один раз, дальше витрина обновляется
	    ТОЛЬКО по своему Event (и по State — на случай снятия базы без Event): одно отложенное
	    task.defer на витрину перечитывает все поля (при "swap" State остаётся "fish", меняется
	    FishUid). Тихие рыбы (первое чтение, "mount") строятся по очереди — не больше
	    BuildPerCheck моделей за проверку, ближние базы первыми; рыбы событий "in" / "swap" —
	    сразу (их видно).
	  • Рыба (TankDisplay.buildFish): копия ReplicatedStorage.Assets.Fish[FishId][Mutation или
	    "Normal"] (незнакомая мутация — "Normal"), масштаб min(MaxScale, Fit / длинная сторона),
	    центр ГАБАРИТА — на Display.FishPoint (Body смещён до 0.88), голова по ±X витрины
	    (SlotIndex % 4 < 2 — к водоросли, она в заднем углу: хвост уходит в пустой угол), поворот
	    Yaw° к проходу; CanCollide, CanQuery, CanTouch, CastShadow — false; атрибуты FishId,
	    Rarity, Mutation, Kg, Value, FishUid, BaseIndex, SlotIndex (радужные переливаются сами:
	    тег RainbowFish, FishingFxController). Не больше 20 деталей (рыба-дракон).
	  • Тихая жизнь — только зацикленные твины (без покадрового Lua): ближе LifeRange — детали
	    приварены к закреплённому Body и один твин его CFrame (покачивание ±Life.Bob stud и
	    ±Life.Turn° вокруг центра рыбы, Sine InOut, Life.TimeMin..TimeMax с, Reverses, бесконечно,
	    случайная фаза); дальше — твин снят, сварки убраны, рыба замерла. Рыба не «шлёпает».
	  • Надпись витрины FxTankTag — BillboardGui на FishPoint + (0, Tag.Lift, −Tag.Forward) в осях
	    витрины: над стеклом и ПЕРЕД его лицевой гранью, ниже потолка галереи (из прохода взгляд на
	    неё не идёт сквозь стекло — стекло прячет надписи за собой; отступление от «прямо над
	    центром» дизайна), Tag.Width × Tag.Height studs + Tag.PixelsX × Tag.PixelsY px,
	    MaxDistance TagRange, без света и AlwaysOnTop: «+$4/с» (BillboardGreen) и «$45 ▲» /
	    «$135 МАКС» (BillboardYellow; Texts.TagValue / TagMax), стиль STYLE §3 «надписи в мире»;
	    цена — TankRules.CurrentValue(Value, AgeAt(GrowFrom, GetServerTimeNow())) раз в TagEvery
	    с (та же цепочка) и только у надписей ближе TagRange. Над закрытой витриной ("locked") на
	    том же месте — тусклое «🔒 Закрыто» (FxTankLock, Texts.SlotLocked, светло-серым Slate):
	    из прохода табличку на тумбе не прочесть.
	  • Надпись садка FxTankSign над передним краем Tank.Glass (выше таблички «АКВАРИУМ»),
	    MaxDistance SignRange: «+$42/с» крупно зелёным, «🐠 4/6» мельче белым (Texts.TankCount) — из
	    атрибутов садка Count / Slots / Income; у свободной базы и до подключения садка (нет Count)
	    спрятана.
	  • Слово у ведра FxPierTank — ТОЛЬКО своя база: BillboardGui на Attachment над Platform.Bucket
	    (низ — Pier.Lift над верхом ведра и рыбьего хвоста BucketFish), Pier.Width × Pier.Height
	    studs + px, MaxDistance Pier.Range: «🐠 4/6» белым и «+$42/с» (BillboardGreen) из атрибутов
	    игрока TankCount / TankSlots / Income; нет TankSlots (данные не загружены) — нет слова.
	    Спрятано, пока FishingState — Bite или Reeling, пока у HUD CounterHold и пока свой
	    персонаж держит HeldFish (как уведомления); снова видно — выскакивает. Прилёт "stored" /
	    "replaced" (FishingState "Caught" с Tank.Result; когда снят CounterHold, а не было его —
	    через ARRIVAL_WAIT с; Этап 4 — TankEvent "Stored" сразу) — один всплеск брызг у края
	    ведра, а слово, когда снова видно, — «удар» (UiFx.punch). Ближе PopRange к ведру (свой
	    персонаж), при доходе > 0 и видимом слове раз в PopEvery с над словом всплывает «+$13»
	    (доход в секунду, Texts.Pop; на Pier.Rise studs за Pier.PopTime с, тает). Кнопки
	    ProximityPrompt у ведра нет (тап в 5 studs от точки рыбалки попал бы в экран рыбалки).
	  • События витрин (базы ближе EventRange; дальше — тихо): "in" — новая рыба вырастает из точки
	    (Fx.From → 1 за Fx.Grow с), брызги и искры цвета редкости (Emit на временном Attachment на
	    Fx.Above над ВЕРХОМ витрины, не внутри стекла), вспышка света у LightBar (свой PointLight,
	    LightBar сервера не трогаем), надпись выскакивает; "sold" — рыба сжимается за Fx.Shrink
	    с, золотые искры, «+$45» поднимается (цена — третье поле Event); "swap" — то же, и новая
	    рыба вырастает на её месте; "mount" и незнакомые — тихо. Не больше Fx.MaxEmitters
	    ParticleEmitter на игрока (лишний вытесняет самый старый; каждый живёт Fx.EmitterLife с).
	  • Кнопки "TankPrompt" чужих баз — Enabled = false только на этом клиенте (сервер всё равно
	    проверяет хозяина); стала своей — Enabled как у сервера (садок подключён — у модели садка
	    есть Slots). Над рынком острова — «РЫНОК +50%!» (Texts.MarketWord, BillboardYellow,
	    MaxDistance Display.MarketWordRange, Display.MarketWord: над вывеской «РЫБНЫЙ РЫНОК»);
	    TankEvent "Sold" у ларька (Place — Id из EconomyConfig.SellPoints) — горсть монет у его
	    весов (если ближе EventRange).
	Соединения: на игрока — AttributeChanged, CharacterAdded (на персонажа — ChildAdded /
	ChildRemoved: HeldFish); у HUD — AttributeChanged (CounterHold); FishingState и TankEvent;
	у каждой построенной базы — по одному AttributeChanged на витрину, садок и модель базы и
	кнопка "TankPrompt" (Enabled). В покое ни одного покадрового соединения (только цепочка
	проверок и зацикленные твины рыб вблизи).
	Атрибуты витрин требуют StreamingEnabled = false (tools/build.luau). Стекло с прозрачностью
	прячет частицы и надписи за собой — эффекты и надписи только над стеклом или снаружи.

	API:
	  TankWorldController:Start(hud)
	  (для тестов и превью)
	  TankWorldController.GetFish(base, slotIndex) -> Model?          -- рыба в витрине (Base_N)
	  TankWorldController.GetTag(base, slotIndex) -> BillboardGui?
	  TankWorldController.GetSign(base) -> BillboardGui?
	  TankWorldController.GetPierWord() -> BillboardGui?
	  TankWorldController.IsBuilt(base) -> boolean
	  TankWorldController.IsAlive(base, slotIndex) -> boolean         -- твин жизни идёт
	  TankWorldController.Stats() -> { bases, fish, tags, life, locks, emitters, lastBuilds, folder }
	  TankWorldController.SetLife(enabled)   -- превью: RbxSim не двигает приваренные детали за Body
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local TankConfig = require(Config:WaitForChild("TankConfig"))
local EconomyConfig = require(Config:WaitForChild("EconomyConfig"))
local UIConfig = require(Config:WaitForChild("UIConfig"))
local TankRules = require(Shared:WaitForChild("TankRules"))
local TextUtil = require(Shared:WaitForChild("TextUtil"))
local UiFx = require(Shared:WaitForChild("UiFx"))
local Net = require(Shared:WaitForChild("Net"))
local Trove = require(Shared:WaitForChild("Util"):WaitForChild("Trove"))
local TankDisplay = require(script.Parent:WaitForChild("TankDisplay"))

local DISPLAY = TankConfig.Display
local PIER = TankConfig.Pier
local FX = DISPLAY.Fx
local TEXTS = TankConfig.Texts
local RATE_SUFFIX = EconomyConfig.Format.Rate
local FOLDER_NAME = "TankWorld"
local ARRIVAL_WAIT = 1 -- прилёт без CounterHold (нет FishingController): всплеск через столько с
local BUSY_STATES: { [string]: boolean } = { Bite = true, Reeling = true }

type Info = {
	state: string,
	uid: string?,
	fishId: string?,
	mutation: string?,
	rarity: string?,
	kg: number?,
	value: number?,
	income: number?,
	growFrom: number?,
	event: string?,
}

type Slot = {
	index: number,
	model: Instance,
	display: BasePart?,
	fishPoint: Attachment?,
	lightBar: BasePart?,
	info: Info?, -- что показываем (nil — пусто)
	fish: Model?,
	uid: string?,
	fishId: string?,
	mutation: string?,
	life: TankDisplay.Life?,
	tweens: { Tween },
	busyUntil: number, -- рыба растёт (os.clock): жизнь не начинаем
	tag: TankDisplay.Tag?,
	tagHolder: Attachment?,
	lockHolder: Attachment?, -- «🔒 Закрыто» над закрытой витриной
	lastEvent: string?,
	pending: boolean, -- отложенное перечитывание уже ждёт
	queued: boolean, -- ждёт тихой постройки
}

type Base = {
	model: Model,
	index: number,
	tank: Model,
	glass: BasePart,
	slots: { Slot },
	trove: any,
	distance: number,
	owner: number,
	sign: TankDisplay.Pair?,
	prompt: ProximityPrompt?,
	leaving: { [Model]: boolean }, -- уходящие рыбы (сжимаются): убрать вместе с базой
}

type Emitter = { emitter: ParticleEmitter, holder: Attachment }

local TankWorldController = {}

local player = Players.LocalPlayer
local started = false
local folder: Folder? = nil
local anchor: BasePart? = nil
local hudGui: ScreenGui? = nil
local bases: { [Model]: Base } = {}
local hiddenPrompts: { [ProximityPrompt]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local emitters: { Emitter } = {}
local rng = Random.new()
local nextTag = 0
local lastBuilds = 0
local lifeEnabled = true
local warned: { [string]: boolean } = {}
local sellPoints: { [string]: Attachment } = {}
-- Слово у ведра своей базы.
local pier = {
	baseIndex = 0,
	trove = Trove.new(),
	word = nil :: TankDisplay.Pair?,
	holder = nil :: Attachment?,
	splashAt = nil :: Vector3?,
	bucket = nil :: Vector3?,
	visible = false,
	punch = false,
	arrival = nil :: { held: boolean }?,
	nextPop = 0,
	heldFish = false,
	characterTrove = Trove.new(),
}

--------------------------------------------------------------------------------
-- Мелочи
--------------------------------------------------------------------------------

local function warnOnce(key: string, message: string)
	if not warned[key] then
		warned[key] = true
		warn(`[TankWorldController] {message}`)
	end
end

-- Точка надписи или эффекта: Attachment на детали-держателе (она в начале координат — его
-- CFrame и есть мировой).
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

-- Откуда смотрим: камера и свой персонаж.
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

local function str(inst: Instance, name: string): string?
	local v = inst:GetAttribute(name)
	return if typeof(v) == "string" and v ~= "" then v else nil
end

local function num(inst: Instance, name: string): number?
	local v = inst:GetAttribute(name)
	return if typeof(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then v else nil
end

-- «+$4/с» → «$4» (сумма в всплывашке «+$4»).
local function amountOf(income10: number): string
	local text = TankRules.FormatRate(income10)
	return string.sub(text, 2, #text - #RATE_SUFFIX)
end

local function rarityColors(rarity: string?): { Color3 }
	local style = rarity and UIConfig.Rarity[rarity]
	if not style then
		return { Color3.new(1, 1, 1), UIConfig.Palette.Sky.Top }
	end
	if style.Rainbow then
		return { UIConfig.Rainbow[1], UIConfig.Rainbow[3], UIConfig.Rainbow[5], UIConfig.Rainbow[6] }
	end
	return { Color3.new(1, 1, 1), style.Top, style.Bottom }
end

local function rarityLight(rarity: string?): Color3
	local style = rarity and UIConfig.Rarity[rarity]
	if not style then
		return UIConfig.Palette.Water.Top
	end
	return if style.Rainbow then UIConfig.Rainbow[6] else style.Bottom
end

--------------------------------------------------------------------------------
-- Частицы (не больше Fx.MaxEmitters сразу)
--------------------------------------------------------------------------------

local function burst(at: Vector3, kind: string, colors: { Color3 }?, count: number)
	while #emitters >= FX.MaxEmitters do
		local oldest = table.remove(emitters, 1)
		if oldest then
			oldest.holder:Destroy()
		end
	end
	local point = holder("FxBurst", CFrame.new(at))
	if not point then
		return
	end
	local emitter = TankDisplay.emitter(point, kind, colors)
	local entry: Emitter = { emitter = emitter, holder = point }
	table.insert(emitters, entry)
	TankDisplay.emit(emitter, count)
	task.delay(FX.EmitterLife, function()
		local i = table.find(emitters, entry)
		if i then
			table.remove(emitters, i)
		end
		point:Destroy()
	end)
end

-- Всплывающая сумма над точкой at (мир): поднимается на lift studs за time с, потом удаляется.
type RiseSize = { Width: number, Height: number, PixelsX: number, PixelsY: number }

local function riseAt(
	at: Vector3,
	text: string,
	look: TankDisplay.Look,
	spec: RiseSize,
	lift: number,
	time: number,
	range: number
)
	local point = holder("FxPop", CFrame.new(at))
	if not point then
		return
	end
	local size = UDim2.new(spec.Width, spec.PixelsX, spec.Height, spec.PixelsY)
	TankDisplay.rise(point, text, look, size, lift, time, range)
	task.delay(time + 0.1, function()
		point:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Витрина: рыба и надпись
--------------------------------------------------------------------------------

local function readSlot(model: Instance): Info
	local state = str(model, "State") or "empty"
	return {
		state = state,
		uid = str(model, "FishUid"),
		fishId = str(model, "FishId"),
		mutation = str(model, "Mutation"),
		rarity = str(model, "Rarity"),
		kg = num(model, "Kg"),
		value = num(model, "Value"),
		income = num(model, "Income"),
		growFrom = num(model, "GrowFrom"),
		event = str(model, "Event"),
	}
end

-- "<n>|<вид>|<поле>" → вид, поле.
local function parseEvent(value: string?): (string?, string?)
	if not value then
		return nil, nil
	end
	local kind, detail = string.match(value, "^%d+|(%a+)|(.*)$")
	return kind, detail
end

-- Голова — к водоросли (она в заднем углу витрины, сторона — по SlotIndex % 4, как в шаблоне).
local function headOf(index: number): number
	return if index % 4 < 2 then 1 else -1
end

-- Над верхом витрины и перед лицевой гранью стекла (из прохода — не сквозь стекло).
local function topOf(slot: Slot): Vector3?
	local display = slot.display
	if not display then
		return nil
	end
	local size = display.Size
	return (display.CFrame * CFrame.new(0, size.Y / 2 + FX.Above, -(size.Z / 2 + FX.Forward))).Position
end

-- Где надпись витрины: FishPoint + (0, Tag.Lift, −Tag.Forward) в осях витрины.
local function tagPoint(slot: Slot): Vector3?
	local point = slot.fishPoint
	if not point then
		return nil
	end
	return (point.WorldCFrame * CFrame.new(0, DISPLAY.Tag.Lift, -DISPLAY.Tag.Forward)).Position
end

local function updateTag(slot: Slot)
	local tag, info = slot.tag, slot.info
	if not tag or not info then
		return
	end
	local income10 = math.round((info.income or 0) * 10)
	local age = TankRules.AgeAt(info.growFrom or Workspace:GetServerTimeNow(), Workspace:GetServerTimeNow())
	local price = TankRules.FormatMoney(TankRules.CurrentValue(info.value or 0, age))
	local template = if TankRules.IsMaxed(age) then TEXTS.TagMax else TEXTS.TagValue
	TankDisplay.setTag(tag, TankRules.FormatRate(income10), TextUtil.fill(template, { price = price, max = TEXTS.Max }))
end

local function cancelTweens(slot: Slot)
	for _, tween in slot.tweens do
		tween:Cancel()
	end
	table.clear(slot.tweens)
end

local function stopLife(slot: Slot)
	local life = slot.life
	if life then
		slot.life = nil
		TankDisplay.stopLife(life)
	end
end

-- Убрать рыбу витрины: сразу (тихо) или сжимаясь (продана / заменена).
local function dropFish(base: Base, slot: Slot, animate: boolean)
	local model = slot.fish
	stopLife(slot)
	cancelTweens(slot)
	slot.fish, slot.uid, slot.fishId, slot.mutation = nil, nil, nil, nil
	local tagHolder, tag = slot.tagHolder, slot.tag
	slot.tag, slot.tagHolder = nil, nil
	if tagHolder then
		if animate and tag then
			UiFx.popOut(tag.plate, { time = FX.TagOut })
			task.delay(FX.TagOut + 0.05, function()
				tagHolder:Destroy()
			end)
		else
			tagHolder:Destroy()
		end
	end
	if not model then
		return
	end
	if animate then
		base.leaving[model] = true
		TankDisplay.scaleParts(model, 1, 0, FX.Shrink, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.delay(FX.Shrink + 0.02, function()
			base.leaving[model] = nil
			model:Destroy()
		end)
	else
		model:Destroy()
	end
end

-- Показать рыбу из slot.info; grow — вырастает (событие), delay — после стольких секунд.
local function showFish(base: Base, slot: Slot, grow: boolean, delay: number)
	local info = slot.info
	local root = folder
	if not info or not info.fishId or not slot.fishPoint or not root then
		return
	end
	local template = TankDisplay.template(info.fishId, info.mutation)
	if not template then
		return
	end
	local model = TankDisplay.buildFish(template, slot.fishPoint, headOf(slot.index), {
		FishId = info.fishId,
		Rarity = info.rarity,
		Mutation = info.mutation,
		Kg = info.kg,
		Value = info.value,
		FishUid = info.uid,
		BaseIndex = base.index,
		SlotIndex = slot.index,
	})
	if not model then
		return
	end
	model.Name = `DisplayFish_{base.index}_{slot.index}`
	model.Parent = root
	slot.fish, slot.uid, slot.fishId, slot.mutation = model, info.uid, info.fishId, info.mutation
	slot.busyUntil = 0
	local tagAt = tagPoint(slot) :: Vector3
	local tagHolder = holder("FxTankTag", CFrame.new(tagAt))
	if tagHolder then
		slot.tagHolder = tagHolder
		slot.tag = TankDisplay.tag(tagHolder)
		updateTag(slot)
	end
	if grow then
		-- (при замене новая рыба ждёт крошкой, пока старая сжимается)
		slot.tweens =
			TankDisplay.scaleParts(model, FX.From, 1, FX.Grow, Enum.EasingStyle.Back, Enum.EasingDirection.Out, delay)
		slot.busyUntil = os.clock() + delay + FX.Grow + 0.05
		local tag = slot.tag
		if tag then
			UiFx.popIn(tag.plate, { from = 0, delay = delay + FX.Grow * 0.5 })
		end
	end
end

-- Прилёт рыбы в витрину: брызги и искры над её верхом, вспышка у LightBar.
local function arrivalFx(slot: Slot, splash: boolean)
	local info = slot.info
	local top = topOf(slot)
	if not top then
		return
	end
	if splash then
		burst(top, "splash", nil, FX.Splash)
	end
	burst(top, "sparkle", rarityColors(info and info.rarity), FX.Sparkle)
	local bar = slot.lightBar
	if bar then
		local point = holder("FxFlash", CFrame.new(bar.Position))
		if point then
			TankDisplay.flash(point, rarityLight(info and info.rarity))
			task.delay(FX.FlashTime + 0.1, function()
				point:Destroy()
			end)
		end
	end
end

-- Рыбу продали / заменили: золотые искры и «+$45» над витриной.
local function saleFx(slot: Slot, price: number?)
	local top, tag = topOf(slot), tagPoint(slot)
	if not top or not tag then
		return
	end
	burst(top, "sparkle", { Color3.new(1, 1, 1), UIConfig.Palette.Gold.Top, UIConfig.Palette.Gold.Bottom }, FX.Sparkle)
	if price and price > 0 then
		-- (с места надписи витрины: она в этот миг уходит)
		local text = TextUtil.fill(TEXTS.Pop, { amount = TankRules.FormatMoney(price) })
		riseAt(tag, text, UIConfig.BillboardYellow, FX.RiseSize, FX.Rise, FX.RiseTime, DISPLAY.EventRange)
	end
end

-- Закрытая витрина (Этап 5 откроет её): тусклое слово «🔒 Закрыто» на месте надписи витрины.
local function setLocked(slot: Slot, locked: boolean)
	local current = slot.lockHolder
	if locked and not current then
		local at = tagPoint(slot)
		local point = at and holder("FxTankLock", CFrame.new(at))
		if point then
			slot.lockHolder = point
			TankDisplay.lock(point, TEXTS.SlotLocked)
		end
	elseif not locked and current then
		slot.lockHolder = nil
		current:Destroy()
	end
end

-- Перечитать витрину (после её Event / State или при постройке базы).
local function refresh(base: Base, slot: Slot)
	local info = readSlot(slot.model)
	local event = info.event
	local kind, detail = nil, nil
	if event ~= nil and event ~= slot.lastEvent then
		kind, detail = parseEvent(event)
	end
	slot.lastEvent = event
	local loud = kind ~= nil and kind ~= "mount" and base.distance <= DISPLAY.EventRange
	local fishId = info.fishId
	local wanted = info.state == "fish" and fishId ~= nil and TankDisplay.template(fishId, info.mutation) ~= nil
	local same = wanted
		and slot.fish ~= nil
		and slot.uid == info.uid
		and slot.fishId == info.fishId
		and slot.mutation == info.mutation
	slot.info = if wanted then info else nil
	setLocked(slot, info.state == "locked")
	if same then
		updateTag(slot)
		return
	end
	local leaving = loud and (kind == "sold" or kind == "swap")
	if slot.fish then
		dropFish(base, slot, leaving)
	end
	if leaving then
		saleFx(slot, tonumber(detail))
	end
	slot.queued = false
	if not wanted then
		return
	end
	if loud and (kind == "in" or kind == "swap") then
		local delay = if kind == "swap" then FX.Shrink else 0
		showFish(base, slot, true, delay)
		arrivalFx(slot, kind == "in")
	else
		slot.queued = true
	end
end

local function schedule(base: Base, slot: Slot)
	if slot.pending then
		return
	end
	slot.pending = true
	task.defer(function()
		slot.pending = false
		if bases[base.model] == base then
			refresh(base, slot)
		end
	end)
end

--------------------------------------------------------------------------------
-- База: постройка, хозяин, надпись садка, кнопка
--------------------------------------------------------------------------------

local function updateSign(base: Base)
	local tank = base.tank
	local count, slots = num(tank, "Count"), num(tank, "Slots")
	local show = base.owner > 0 and count ~= nil and slots ~= nil
	if show and not base.sign then
		local glass = base.glass
		local at = glass.CFrame
			* CFrame.new(0, glass.Size.Y / 2 + DISPLAY.Sign.Lift, -glass.Size.Z / 2 + DISPLAY.Sign.Inset)
		local point = holder("FxTankSign", CFrame.new(at.Position))
		if point then
			base.trove:Add(point)
			base.sign = TankDisplay.sign(point)
		end
	end
	local sign = base.sign
	if not sign then
		return
	end
	sign.gui.Enabled = show
	if show then
		local income10 = math.round((num(tank, "Income") or 0) * 10)
		TankDisplay.setPair(
			sign,
			TankRules.FormatRate(income10),
			TextUtil.fill(TEXTS.TankCount, { count = count or 0, slots = slots or 0 })
		)
	end
end

-- Кнопка садка: у чужой базы спрятана на этом клиенте; стала своей — как у сервера.
local function applyPrompt(base: Base)
	local prompt = base.prompt
	if not prompt then
		local point = base.glass:FindFirstChild("PromptAttachment")
		local found = point and point:FindFirstChild("TankPrompt")
		if not (found and found:IsA("ProximityPrompt")) then
			return
		end
		prompt = found
		base.prompt = found
		base.trove:Connect(found:GetPropertyChangedSignal("Enabled"), function()
			if bases[base.model] == base and base.owner ~= player.UserId and found.Enabled then
				found.Enabled = false
			end
		end)
	end
	local p = prompt :: ProximityPrompt
	if base.owner ~= player.UserId then
		hiddenPrompts[p] = true
		if p.Enabled then
			p.Enabled = false
		end
	elseif hiddenPrompts[p] then
		hiddenPrompts[p] = nil
		p.Enabled = base.tank:GetAttribute("Slots") ~= nil
	end
end

local function ownerChanged(base: Base)
	local owner = num(base.model, "OwnerUserId") or 0
	base.owner = owner
	updateSign(base)
	applyPrompt(base)
	-- (снятая база без Event: витрины перечитываются все)
	for _, slot in base.slots do
		schedule(base, slot)
	end
end

local function build(model: Model, distance: number): Base?
	local tank = model:FindFirstChild("Tank")
	local glass = tank and tank:FindFirstChild("Glass")
	local slotsFolder = tank and tank:FindFirstChild("Slots")
	if not (tank and tank:IsA("Model") and glass and glass:IsA("BasePart") and slotsFolder) then
		warnOnce(
			`base:{model.Name}`,
			`у {model.Name} нет Tank.Glass / Tank.Slots — витрины не показываю`
		)
		return nil
	end
	local base: Base = {
		model = model,
		index = num(model, "BaseIndex") or 0,
		tank = tank,
		glass = glass,
		slots = {},
		trove = Trove.new(),
		distance = distance,
		owner = num(model, "OwnerUserId") or 0,
		sign = nil,
		prompt = nil,
		leaving = {},
	}
	bases[model] = base
	for index = 1, TankConfig.MaxSlots do
		local slotModel = slotsFolder:FindFirstChild(`Slot_{index}`)
		if not slotModel then
			continue
		end
		local display = slotModel:FindFirstChild("Display")
		local fishPoint = display and display:FindFirstChild("FishPoint")
		local bar = slotModel:FindFirstChild("LightBar")
		local slot: Slot = {
			index = index,
			model = slotModel,
			display = if display and display:IsA("BasePart") then display else nil,
			fishPoint = if fishPoint and fishPoint:IsA("Attachment") then fishPoint else nil,
			lightBar = if bar and bar:IsA("BasePart") then bar else nil,
			info = nil,
			fish = nil,
			uid = nil,
			fishId = nil,
			mutation = nil,
			life = nil,
			tweens = {},
			busyUntil = 0,
			tag = nil,
			tagHolder = nil,
			lockHolder = nil,
			lastEvent = nil,
			pending = false,
			queued = false,
		}
		table.insert(base.slots, slot)
		base.trove:Connect(slotModel.AttributeChanged, function(name: string)
			if name == "Event" or name == "State" then
				schedule(base, slot)
			end
		end)
		-- первое чтение: тихо (текущее Event — уже «старое»)
		slot.lastEvent = str(slotModel, "Event")
		refresh(base, slot)
	end
	base.trove:Connect(model.AttributeChanged, function(name: string)
		if name == "OwnerUserId" then
			ownerChanged(base)
		end
	end)
	base.trove:Connect(tank.AttributeChanged, function(name: string)
		if name == "Count" or name == "Slots" or name == "Income" then
			updateSign(base)
			applyPrompt(base)
		end
	end)
	base.trove:Add(function()
		for _, slot in base.slots do
			dropFish(base, slot, false)
			setLocked(slot, false)
			slot.info, slot.queued = nil, false
		end
		for leaving in base.leaving do
			leaving:Destroy()
		end
		table.clear(base.leaving)
		base.sign = nil
	end)
	updateSign(base)
	applyPrompt(base)
	return base
end

local function teardown(base: Base)
	if bases[base.model] == base then
		bases[base.model] = nil
	end
	base.trove:Clean()
end

--------------------------------------------------------------------------------
-- Слово у ведра своей базы
--------------------------------------------------------------------------------

-- Верх детали в мире (её габарит по Y).
local function topY(part: BasePart): number
	local cf, size = part.CFrame, part.Size
	local half = math.abs(cf.XVector.Y) * size.X / 2
		+ math.abs(cf.YVector.Y) * size.Y / 2
		+ math.abs(cf.ZVector.Y) * size.Z / 2
	return cf.Position.Y + half
end

local function refreshPier()
	local word = pier.word
	if not word then
		return
	end
	local slots = num(player, "TankSlots")
	local state = str(player, "FishingState")
	local hud = hudGui
	local busy = (state ~= nil and BUSY_STATES[state] == true)
		or (hud ~= nil and hud:GetAttribute("CounterHold") ~= nil)
		or pier.heldFish
	local show = slots ~= nil and not busy
	if slots ~= nil then
		local count = num(player, "TankCount") or 0
		local income10 = math.round((num(player, "Income") or 0) * 10)
		TankDisplay.setPair(
			word,
			TextUtil.fill(TEXTS.TankCount, { count = count, slots = slots }),
			TankRules.FormatRate(income10)
		)
	end
	if show == pier.visible then
		return
	end
	pier.visible = show
	word.gui.Enabled = show
	if show then
		if pier.punch then
			pier.punch = false
			UiFx.punch(word.plate, { from = 0.5, peak = 1.22 })
		else
			UiFx.popIn(word.plate, { from = 0.6, time = 0.25 })
		end
	end
end

-- Рыба легла в садок: всплеск у ведра; слово «ударит», когда его снова видно.
local function arrive()
	pier.arrival = nil
	local at = pier.splashAt
	if at then
		burst(at, "splash", nil, PIER.Splash)
	end
	pier.punch = true
	if pier.visible and pier.word then
		pier.punch = false
		UiFx.punch(pier.word.plate, { from = 0.5, peak = 1.22 })
	end
end

local function setupPier()
	local index = num(player, "BaseIndex") or 0
	if index == pier.baseIndex and pier.word then
		return
	end
	pier.trove:Clean()
	pier.word, pier.holder, pier.splashAt, pier.bucket = nil, nil, nil, nil
	pier.visible = false
	pier.baseIndex = index
	local basesFolder = Workspace:FindFirstChild("Bases")
	local base = index > 0 and basesFolder and basesFolder:FindFirstChild(`Base_{index}`)
	local platform = base and base:FindFirstChild("Platform")
	local bucket = platform and platform:FindFirstChild("Bucket")
	if not (bucket and bucket:IsA("BasePart")) then
		if index > 0 then
			warnOnce(
				"bucket",
				`у Base_{index} нет Platform.Bucket — слова садка у ведра не будет`
			)
		end
		return
	end
	local top = topY(bucket)
	local tail = (platform :: Instance):FindFirstChild("BucketFish")
	if tail and tail:IsA("BasePart") then
		top = math.max(top, topY(tail))
	end
	local p = bucket.Position
	-- чуть дальше от места рыбалки, чем ведро (с камеры рыбалки — правее лески и поплавка)
	local spot = (base :: Instance):FindFirstChild("FishingSpot")
	local away = if spot and spot:IsA("BasePart")
		then Vector3.new(p.X - spot.Position.X, 0, p.Z - spot.Position.Z)
		else Vector3.zero
	away = if away.Magnitude > 1e-3 then away.Unit * PIER.Out else Vector3.zero
	local point = holder("FxPierTank", CFrame.new(p.X + away.X, top + PIER.Lift + PIER.Height / 2, p.Z + away.Z))
	if not point then
		return
	end
	pier.trove:Add(point)
	pier.holder = point
	pier.splashAt = Vector3.new(p.X, topY(bucket) + 0.1, p.Z)
	pier.bucket = p
	local word = TankDisplay.pier(point)
	word.gui.Enabled = false
	pier.word = word
	refreshPier()
end

local function watchCharacter(character: Model?)
	pier.characterTrove:Clean()
	pier.heldFish = false
	if not character then
		refreshPier()
		return
	end
	local function update()
		local held = character:FindFirstChild("HeldFish") ~= nil
		if held ~= pier.heldFish then
			pier.heldFish = held
			refreshPier()
		end
	end
	pier.characterTrove:Connect(character.ChildAdded, update)
	pier.characterTrove:Connect(character.ChildRemoved, update)
	update()
end

local function popIncome()
	local word, at = pier.word, pier.holder
	if not word or not at or not pier.visible then
		return
	end
	local income10 = math.round((num(player, "Income") or 0) * 10)
	if income10 <= 0 then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local bucket = pier.bucket
	if not (root and root:IsA("BasePart") and bucket) or (root.Position - bucket).Magnitude > PIER.PopRange then
		return
	end
	local text = TextUtil.fill(TEXTS.Pop, { amount = amountOf(income10) })
	local from = at.WorldPosition + Vector3.new(0, PIER.Height * 0.5, 0)
	riseAt(from, text, UIConfig.BillboardGreen, PIER.PopSize, PIER.Rise, PIER.PopTime, PIER.Range)
end

--------------------------------------------------------------------------------
-- Рынок
--------------------------------------------------------------------------------

local function findPath(path: string): Instance?
	local node: Instance? = Workspace
	for _, name in string.split(path, ".") do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function setupMarket()
	local bonus = EconomyConfig.MarketRatePct - 100
	for _, point in EconomyConfig.SellPoints do
		local found = findPath(point.Path)
		if not (found and found:IsA("Attachment")) then
			warnOnce(`sell:{point.Id}`, `нет {point.Path} — ларька {point.Id} в мире не видно`)
			continue
		end
		sellPoints[point.Id] = found
		if point.Word then
			local spec = DISPLAY.MarketWord
			local cf = found.WorldCFrame
			local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
			look = if look.Magnitude > 1e-3 then look.Unit else Vector3.zero
			local at = cf.Position + Vector3.new(0, spec.Up, 0) + look * spec.Forward
			local word = holder("FxMarketWord", CFrame.new(at))
			if word then
				TankDisplay.market(word, TextUtil.fill(TEXTS.MarketWord, { bonus = bonus }))
			end
		end
	end
end

local function onTankEvent(kind: any, data: any)
	if kind == "Stored" then
		arrive()
	elseif kind == "Sold" and type(data) == "table" then
		local place = data.Place
		local point = if typeof(place) == "string" then sellPoints[place] else nil
		if point then
			local cam, body = viewers()
			if distanceFrom(point.WorldPosition, cam, body) <= DISPLAY.EventRange then
				burst(point.WorldPosition + Vector3.new(0, 1.2, 0), "coins", nil, FX.Coins)
			end
		end
	end
end

local function onFishingState(state: any, data: any)
	if state ~= "Caught" or type(data) ~= "table" or type(data.Tank) ~= "table" then
		return
	end
	local result = data.Tank.Result
	if result ~= "stored" and result ~= "replaced" then
		return
	end
	-- (FishingController ставит CounterHold на этот же "Caught" — до нас или после)
	local hud = hudGui
	local arrival = { held = hud ~= nil and hud:GetAttribute("CounterHold") ~= nil }
	pier.arrival = arrival
	task.delay(ARRIVAL_WAIT, function()
		if pier.arrival == arrival and not arrival.held and not (hud and hud:GetAttribute("CounterHold") ~= nil) then
			arrive()
		end
	end)
end

--------------------------------------------------------------------------------
-- Проверка раз в CheckEvery
--------------------------------------------------------------------------------

local function check()
	local cam, body = viewers()
	local basesFolder = Workspace:FindFirstChild("Bases")
	-- снятые со сцены базы
	for model, base in bases do
		if model.Parent == nil then
			teardown(base)
		end
	end
	if basesFolder then
		for _, child in basesFolder:GetChildren() do
			if not child:IsA("Model") then
				continue
			end
			local tank = child:FindFirstChild("Tank")
			local glass = tank and tank:FindFirstChild("Glass")
			if not (glass and glass:IsA("BasePart")) then
				continue
			end
			local d = distanceFrom(glass.Position, cam, body)
			local base = bases[child]
			if base then
				base.distance = d
				if d > DISPLAY.DropRange then
					teardown(base)
				end
			elseif d <= DISPLAY.Range then
				build(child, d)
			end
		end
	end
	-- тихие постройки: ближние базы первыми, не больше BuildPerCheck
	local order = {}
	for _, base in bases do
		table.insert(order, base)
	end
	table.sort(order, function(a: Base, b: Base)
		return a.distance < b.distance
	end)
	local built = 0
	local now = os.clock()
	local tagTime = now >= nextTag
	if tagTime then
		nextTag = now + DISPLAY.TagEvery
	end
	for _, base in order do
		for _, slot in base.slots do
			if slot.queued and built < DISPLAY.BuildPerCheck then
				slot.queued = false
				showFish(base, slot, false, 0)
				if slot.fish then
					built += 1
				end
			end
			local model, point = slot.fish, slot.fishPoint
			if model and point then
				local near = lifeEnabled and distanceFrom(point.WorldPosition, cam, body) <= DISPLAY.LifeRange
				if near and not slot.life and now >= slot.busyUntil then
					cancelTweens(slot)
					slot.life = TankDisplay.startLife(model, rng)
				elseif not near and slot.life then
					stopLife(slot)
				end
			end
			local tagHolder = slot.tagHolder
			if tagTime and tagHolder and distanceFrom(tagHolder.WorldPosition, cam, body) <= DISPLAY.TagRange then
				updateTag(slot)
			end
		end
		if not base.prompt then
			applyPrompt(base)
		end
	end
	lastBuilds = built
	-- доход над ведром
	if now >= pier.nextPop then
		pier.nextPop = now + PIER.PopEvery
		popIncome()
	end
end

local function loop()
	local ok, err = pcall(check)
	if not ok then
		warnOnce(`check:{err}`, `проверка упала: {err}`)
	end
	task.delay(DISPLAY.CheckEvery, loop)
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

local function slotOf(base: Instance, index: number): Slot?
	local state = bases[base :: Model]
	if not state then
		return nil
	end
	for _, slot in state.slots do
		if slot.index == index then
			return slot
		end
	end
	return nil
end

function TankWorldController.GetFish(base: Instance, index: number): Model?
	local slot = slotOf(base, index)
	return slot and slot.fish
end

function TankWorldController.GetTag(base: Instance, index: number): BillboardGui?
	local slot = slotOf(base, index)
	local tag = slot and slot.tag
	return tag and tag.gui
end

function TankWorldController.GetSign(base: Instance): BillboardGui?
	local state = bases[base :: Model]
	local sign = state and state.sign
	return sign and sign.gui
end

function TankWorldController.GetPierWord(): BillboardGui?
	local word = pier.word
	return word and word.gui
end

function TankWorldController.IsBuilt(base: Instance): boolean
	return bases[base :: Model] ~= nil
end

function TankWorldController.IsAlive(base: Instance, index: number): boolean
	local slot = slotOf(base, index)
	return slot ~= nil and slot.life ~= nil
end

-- Превью (tools/preview): RbxSim не двигает приваренные детали за Body — для кадров жизнь
-- выключают, рыбы стоят в позе покоя.
function TankWorldController.SetLife(enabled: boolean)
	lifeEnabled = enabled
	if not enabled then
		for _, base in bases do
			for _, slot in base.slots do
				stopLife(slot)
			end
		end
	end
end

function TankWorldController.Stats(): { [string]: any }
	local count = { bases = 0, fish = 0, tags = 0, life = 0, locks = 0 }
	for _, base in bases do
		count.bases += 1
		for _, slot in base.slots do
			count.fish += if slot.fish then 1 else 0
			count.tags += if slot.tag then 1 else 0
			count.life += if slot.life then 1 else 0
			count.locks += if slot.lockHolder then 1 else 0
		end
	end
	return {
		bases = count.bases,
		fish = count.fish,
		tags = count.tags,
		life = count.life,
		locks = count.locks,
		emitters = #emitters,
		lastBuilds = lastBuilds,
		folder = folder,
	}
end

function TankWorldController:Start(hud: ScreenGui)
	if started then
		return
	end
	started = true
	hudGui = hud
	local root = Instance.new("Folder")
	root.Name = FOLDER_NAME
	root.Parent = Workspace
	folder = root
	-- деталь-держатель Attachment'ов надписей и эффектов: в начале координат, невидимая
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

	player.AttributeChanged:Connect(function(name: string)
		if name == "BaseIndex" then
			setupPier()
		elseif name == "TankCount" or name == "TankSlots" or name == "Income" or name == "FishingState" then
			refreshPier()
		end
	end)
	hud.AttributeChanged:Connect(function(name: string)
		if name ~= "CounterHold" then
			return
		end
		local arrival = pier.arrival
		if arrival then
			if hud:GetAttribute("CounterHold") ~= nil then
				arrival.held = true
			else
				arrive()
			end
		end
		refreshPier()
	end)
	player.CharacterAdded:Connect(watchCharacter)
	watchCharacter(player.Character)
	Net.Event("FishingState").OnClientEvent:Connect(onFishingState)
	Net.Event("TankEvent").OnClientEvent:Connect(onTankEvent)
	setupMarket()
	setupPier()
	task.defer(loop)
end

return TankWorldController
