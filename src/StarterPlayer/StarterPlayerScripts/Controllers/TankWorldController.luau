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
	    Rarity, Mutation, Kg, Value, FishUid, BaseIndex, SlotIndex; у радужной тег RainbowFish
	    шаблона снят (атрибут Rainbow = true — см. жизнь). Не больше 20 деталей (рыба-дракон).
	  • Тихая жизнь — только зацикленные твины (без своего покадрового Lua), с запасом: ближе
	    LifeRange рыба оживает — детали приварены к закреплённому Body и один твин его CFrame
	    (покачивание ±Life.Bob stud и ±Life.Turn° вокруг центра рыбы, Sine InOut,
	    Life.TimeMin..TimeMax с, Reverses, бесконечно, случайная фаза), — замирает только дальше
	    LifeDrop (твин снят, сварки убраны; без дребезга, когда камера кружит у границы). Рыба не
	    «шлёпает». Радужная переливается, только пока жива: на это время ей возвращают тег
	    RainbowFish, и FishingFxController перекрашивает её покадрово (его Heartbeat) — дальше
	    LifeDrop тег снят, цвета застывают, Heartbeat отпущен.
	  • Надпись витрины FxTankTag — BillboardGui на FishPoint + (0, Tag.Lift, −Tag.Forward) в осях
	    витрины: ПЕРЕД лицевой гранью стекла, на высоте светящейся планки LightBar — с камеры
	    прохода планка идёт между двумя строками, как черта, — и ниже потолка галереи (из прохода
	    взгляд на неё не идёт сквозь стекло — стекло прячет надписи за собой; отступление от
	    «прямо над центром» дизайна), Tag.Width × Tag.Height studs + Tag.PixelsX × Tag.PixelsY px,
	    обводка Tag.Outline (толще обычной: буквы на неоне), MaxDistance TagShow (дальше надписи
	    соседних витрин прохода сливаются в кашу), без света и AlwaysOnTop: «+$4/с»
	    (BillboardGreen) и «$45» / «$135 МАКС» (BillboardYellow; Texts.TagValue / TagMax), стиль
	    STYLE §3 «надписи в мире»; буквы не крупнее TankDisplay.tagCap(высота экрана) — вблизи
	    растёт рамка, а не буквы (надпись не громче кошелька; потолок пересчитывается, когда
	    меняется размер экрана);
	    цена — TankRules.CurrentValue(Value, AgeAt(GrowFrom, GetServerTimeNow())) раз в TagEvery
	    с (та же цепочка) и только у надписей ближе TagRange (≥ TagShow: показалась — уже свежая).
	    Закрытые витрины ("locked") — тусклое «🔒 Закрыто» (FxTankLock, Texts.SlotLocked,
	    светло-серым Slate) ОДНО на галерею: над первой закрытой витриной (её SlotIndex — самый
	    младший из закрытых этой стороны двора, рядом с открытыми рядами; сторона — знак X витрины
	    в осях Tank.Glass), перед пустым стеклом, на FishPoint + (0, Tag.LockLift, −Tag.Forward) —
	    как табличка на витрине магазина, ниже надписей прохода; MaxDistance LockRange — видно и
	    от ворот двора. Остальным закрытым хватает таблички «🔒 Закрыто» на тумбе и тусклой планки
	    (три одинаковых слова в перспективе прохода сливались в «За🔒рыто»); Этап 5 открыл витрину
	    — слово переходит на следующую.
	  • Надпись садка FxTankSign над передним краем Tank.Glass (выше таблички «АКВАРИУМ»),
	    MaxDistance SignRange: «+$42/с» крупно зелёным, «🐠 4/6» мельче белым (Texts.TankCount) — из
	    атрибутов садка Count / Slots / Income; у свободной базы и до подключения садка (нет Count)
	    спрятана.
	  • Слово у ведра FxPierTank — ТОЛЬКО своя база: BillboardGui на Attachment над Platform.Bucket
	    (низ — Pier.Lift над верхом ведра и рыбьего хвоста BucketFish, на Pier.Out дальше от места
	    рыбалки: с камеры рыбалки — правее удочки и лески, выше кнопки «СМОТАТЬ»), Pier.Width ×
	    Pier.Height studs + px, MaxDistance Pier.Range: «🐠 4/6» белым и «+$42/с» (BillboardGreen) из атрибутов
	    игрока TankCount / TankSlots / Income; нет TankSlots (данные не загружены) — нет слова.
	    Спрятано, пока FishingState — Bite или Reeling, пока у HUD CounterHold и пока свой
	    персонаж держит HeldFish (как уведомления) и ещё Pier.TrophyGap с после (табличка
	    трофея тает там же); снова видно — выскакивает. Прилёт "stored" /
	    "replaced" (FishingState "Caught" с Tank.Result; когда снят CounterHold, а не было его —
	    через ARRIVAL_WAIT с; Этап 4 — TankEvent "Stored" сразу) — один всплеск брызг у края
	    ведра, а слово, когда снова видно, — «удар» (UiFx.punch). Ближе PopRange к ведру (свой
	    персонаж), при доходе > 0 и видимом слове раз в PopEvery с над словом всплывает «+$13»
	    (доход в секунду, Texts.Pop; на Pier.Rise studs за Pier.PopTime с, тает). Кнопки
	    ProximityPrompt у ведра нет (тап в 5 studs от точки рыбалки попал бы в экран рыбалки).
	  • Слова не под HUD (Display.Clear): кошелёк — тем же зелёным курсивом, и слова мира рядом с
	    ним читались одной кашей («+$0$959/с»). В той же цепочке проверок (и сразу, когда слово
	    появилось, и через Clear.ToastWait с после нового уведомления) прямоугольник каждого
	    видимого слова — надписи витрин (буквы — по потолку), «🔒 Закрыто», надпись садка, слово у
	    ведра, слово рынка — на экране (Camera:WorldToScreenPoint; размер — studs × px на stud на
	    этой глубине + px; HUD.IgnoreGuiInset = false, как у AbsolutePosition) сравнивается с
	    видимыми плашками HUD.Status и уведомлениями HUD.Toasts: ближе Clear.Margin px — буквы и
	    обводка тают за Clear.Fade с (TextTransparency / Transparency — Visible, Enabled и
	    UIScale слова у других), снова проявляются за Clear.Show с, только когда слово отошло на
	    Clear.Back px. Слово за камерой, дальше своего MaxDistance или выключенное — как было.
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
	ChildRemoved: HeldFish); у HUD — AttributeChanged (CounterHold), у HUD.Toasts — ChildAdded
	(новое уведомление); FishingState и TankEvent;
	у каждой построенной базы — по одному AttributeChanged на витрину, садок и модель базы и
	кнопка "TankPrompt" (Enabled). В покое ни одного покадрового соединения (только цепочка
	проверок и зацикленные твины рыб вблизи); единственное исключение — живая радужная рыба
	рядом (ближе LifeDrop): её перекрашивает Heartbeat FishingFxController. С места рыбалки
	(≈ 155 studs до своего садка) ни одна рыба не жива.
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
	  TankWorldController.Stats() -> { bases, fish, tags, life, locks, emitters, lastBuilds, folder,
	                                   faded, tagCap, signCap }  -- faded: слов под HUD (тают)
	  TankWorldController.IsFaded(gui) -> boolean    -- слово ушло из-под HUD (Display.Clear)
	  TankWorldController.Lock(base, slotIndex) -> BillboardGui?     -- «🔒 Закрыто» витрины
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
local StealConfig = require(Config:WaitForChild("StealConfig"))
local DefenceConfig = require(Config:WaitForChild("DefenceConfig"))
local TankRules = require(Shared:WaitForChild("TankRules"))
local StealRules = require(Shared:WaitForChild("StealRules"))
local TextUtil = require(Shared:WaitForChild("TextUtil"))
local UiFx = require(Shared:WaitForChild("UiFx"))
local Net = require(Shared:WaitForChild("Net"))
local Trove = require(Shared:WaitForChild("Util"):WaitForChild("Trove"))
local TankDisplay = require(script.Parent:WaitForChild("TankDisplay"))

local DISPLAY = TankConfig.Display
local PIER = TankConfig.Pier
local FX = DISPLAY.Fx
local CLEAR = DISPLAY.Clear
local TEXTS = TankConfig.Texts
local RATE_SUFFIX = EconomyConfig.Format.Rate
local FOLDER_NAME = "TankWorld"
local ARRIVAL_WAIT = 1 -- прилёт без CounterHold (нет FishingController): всплеск через столько с
local BUSY_STATES: { [string]: boolean } = { Bite = true, Reeling = true }
-- Этап 4: кража (канал витрины StealPhase / StealEnd / StealBy) и защиты базы.
local STEAL = DISPLAY.Steal
local WORLD_WORDS = StealConfig.Texts.World
local DEFENCE_WORDS = DefenceConfig.Texts.World
local STEAL_WORD_RANGE = DefenceConfig.World.StealWordRange
local LOCK_LEVELS = #DefenceConfig.Lock.Levels
local BERRY = UIConfig.Palette.Berry
-- Атрибуты модели базы, от которых зависит строка защит надписи садка (DefenceService).
local SIGN_ATTRIBUTES: { [string]: boolean } = {
	ProtectUntil = true,
	ProtectKind = true,
	LockLevel = true,
	HasDog = true,
	HasAlarm = true,
}

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
	phase: string?, -- StealPhase: "hold" | "carry" (Этап 4)
	stealBy: number?, -- StealBy: UserId вора
	stealEnd: number?, -- StealEnd: конец удержания / выноса (серверное время)
}

-- Кража витрины на этом клиенте (Этап 4): слово «КРАДУТ!» / «УНОСЯТ!» с кольцом, красный свет у
-- LightBar, поднятая рыба (удержание); всё — в trove этой кражи.
type Steal = {
	phase: string,
	by: number?,
	trove: any,
	word: TankDisplay.StealWord?,
	holder: Attachment?,
	ringStop: (() -> ())?,
	ringEnd: number?,
	rig: TankDisplay.Rig?, -- рыба поднята и бьётся
	moves: { Tween },
	spot: Vector3?, -- где вор с рыбой (последнее известное; для возврата рыбы)
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
	locked: boolean, -- витрина закрыта (State "locked")
	side: number, -- галерея: знак X витрины в осях Tank.Glass (−1 / 1)
	lockHolder: Attachment?, -- «🔒 Закрыто» над первой закрытой витриной галереи …
	lockGui: BillboardGui?, -- … и само слово
	lastEvent: string?,
	pending: boolean, -- отложенное перечитывание уже ждёт
	queued: boolean, -- ждёт тихой постройки
	steal: Steal?, -- Этап 4: витрину крадут
	rig: TankDisplay.Rig?, -- рыба витрины целиком, в покое (снято при постройке: подъём и полёт)
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
	defence: TankDisplay.Defence?, -- строка защит надписи садка (Этап 4)
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
-- (обычные таблицы с уборкой, не слабые: RbxSim может терять ключи-Instance слабых таблиц)
local hiddenPrompts: { [ProximityPrompt]: boolean } = {}
local emitters: { Emitter } = {}
local rng = Random.new()
local nextTag = 0
local lastBuilds = 0
local lifeEnabled = true
local warned: { [string]: boolean } = {}
local sellPoints: { [string]: Attachment } = {}
local marketWords: { BillboardGui } = {}
-- Слова, ушедшие из-под HUD (тают; Display.Clear), и потолок букв надписей витрин (px).
local faded: { [BillboardGui]: boolean } = {}
local arcs = 0 -- новых копий рыбы в полёте (возврат с головы вора; Steal.MaxArcs)
local tagCap, signCap = TankDisplay.tagCap(390), TankDisplay.signCap(390)
local tagCapHeight = 0 -- высота экрана, по которой они посчитаны
-- Надпись садка у потолка букв: «+$1 234/с» ≈ SIGN_W потолков в ширину, две строки ≈ SIGN_H.
local SIGN_W, SIGN_H = 7, 1.8
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
	heldGen = 0, -- поколение «трофей убран» (Pier.TrophyGap)
	characterTrove = Trove.new(),
	-- Этап 4: у своей базы идёт кража (AlarmState "theft") — «🚨 КРАДУТ!» вместо строк
	base = nil :: Model?,
	alarm = false,
	alarmLabel = nil :: TextLabel?,
	alarmStop = nil :: (() -> ())?,
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

-- toward — куда лететь искрам (мир; nil — вверх): «верх» Attachment'а смотрит туда.
local function burst(at: Vector3, kind: string, colors: { Color3 }?, count: number, toward: Vector3?)
	while #emitters >= FX.MaxEmitters do
		local oldest = table.remove(emitters, 1)
		if oldest then
			oldest.holder:Destroy()
		end
	end
	local frame = CFrame.new(at)
	if toward and toward.Magnitude > 1e-3 then
		frame = CFrame.lookAt(at, at + toward.Unit) * CFrame.Angles(-math.pi / 2, 0, 0)
	end
	local point = holder("FxBurst", frame)
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
-- Слова не под HUD (Display.Clear)
--------------------------------------------------------------------------------

type Rect = { x0: number, y0: number, x1: number, y1: number }

local function rectOf(gui: GuiObject): Rect?
	local p, size = gui.AbsolutePosition, gui.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return nil
	end
	return { x0 = p.X, y0 = p.Y, x1 = p.X + size.X, y1 = p.Y + size.Y }
end

-- Доля выравнивания UIListLayout: Left / Top — 0, Center — 0.5, Right / Bottom — 1.
local function alignShare(name: string): number
	return if name == "Center" then 0.5 elseif name == "Right" or name == "Bottom" then 1 else 0
end

-- Видимые дети рамки с UIListLayout там, где их ставит раскладка, в прямоугольнике рамки box: по
-- своей оси — подряд (LayoutOrder) через Padding, группа и каждый поперёк — по выравниванию. Не
-- по AbsolutePosition детей: так же и в эмуляторе тестов (его раскладка не выравнивает).
local function listItems(frame: Instance, list: UIListLayout, box: Rect, visit: (GuiObject, Rect) -> ())
	local vertical = list.FillDirection == Enum.FillDirection.Vertical
	local w, h = box.x1 - box.x0, box.y1 - box.y0
	local items: { GuiObject } = {}
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") and child.Visible then
			table.insert(items, child)
		end
	end
	table.sort(items, function(a: GuiObject, b: GuiObject)
		return a.LayoutOrder < b.LayoutOrder
	end)
	local gap = list.Padding.Scale * (if vertical then h else w) + list.Padding.Offset
	local total = 0
	for i, item in items do
		local s = item.AbsoluteSize
		total += (if vertical then s.Y else s.X) + (if i > 1 then gap else 0)
	end
	local main = alignShare(if vertical then list.VerticalAlignment.Name else list.HorizontalAlignment.Name)
	local cross = alignShare(if vertical then list.HorizontalAlignment.Name else list.VerticalAlignment.Name)
	local at = ((if vertical then h else w) - total) * main
	for _, item in items do
		local s = item.AbsoluteSize
		local side = (if vertical then w - s.X else h - s.Y) * cross
		local x0 = box.x0 + (if vertical then side else at)
		local y0 = box.y0 + (if vertical then at else side)
		visit(item, { x0 = x0, y0 = y0, x1 = x0 + s.X, y1 = y0 + s.Y })
		at += (if vertical then s.Y else s.X) + gap
	end
end

-- Что на экране HUD не уступает словам мира (px, как AbsolutePosition): видимые плашки стопки
-- статуса — плашка базы и строка кошелька по её содержимому (💵 с числом и доход: MoneyController
-- подгоняет их под текст, а сама строка шире), — и уведомления.
local function hudRects(): { Rect }
	local out: { Rect } = {}
	local hud = hudGui
	if not hud or not hud.Enabled then
		return out
	end
	local status = hud:FindFirstChild("Status")
	local stack = status and status:FindFirstChildOfClass("UIListLayout")
	local box = if status and status:IsA("GuiObject") and status.Visible then rectOf(status) else nil
	if status and stack and box then
		listItems(status, stack, box, function(item: GuiObject, r: Rect)
			local row = if item.Name == "Wallet" then item:FindFirstChildOfClass("UIListLayout") else nil
			if row then
				listItems(item, row, r, function(_, part: Rect)
					table.insert(out, part)
				end)
			else
				table.insert(out, r)
			end
			-- Этап 4: фишка щита «🛡️ 0:42» свисает с правого конца плашки базы (там, где плашку
			-- ставит раскладка: её сдвиг от плашки — по AbsolutePosition обеих)
			local chip = if item.Name == "BaseBadge" then item:FindFirstChild("ShieldChip") else nil
			if chip and chip:IsA("GuiObject") and chip.Visible then
				local own = rectOf(chip)
				if own then
					local dx, dy = r.x0 - item.AbsolutePosition.X, r.y0 - item.AbsolutePosition.Y
					table.insert(out, { x0 = own.x0 + dx, y0 = own.y0 + dy, x1 = own.x1 + dx, y1 = own.y1 + dy })
				end
			end
		end)
	end
	-- Этап 4: полоса вора и тревога хозяина — по видимым частям (значок свисает с плашки,
	-- «таблетка» тревоги стоит отдельно)
	for _, name in { "TheftBar", "TheftAlert" } do
		local root = hud:FindFirstChild(name)
		if root and root:IsA("GuiObject") and root.Visible then
			for _, child in root:GetChildren() do
				local r = if child:IsA("GuiObject") and child.Visible then rectOf(child) else nil
				if r then
					table.insert(out, r)
				end
			end
		end
	end
	local toasts = hud:FindFirstChild("Toasts")
	if toasts and toasts:IsA("GuiObject") and toasts.Visible then
		for _, item in toasts:GetChildren() do
			local r = if item.Name == "Toast" and item:IsA("GuiObject") and item.Visible then rectOf(item) else nil
			if r then
				table.insert(out, r)
			end
		end
	end
	return out
end

-- Прямоугольник слова на экране (px) или nil — его не видно (выключено, за камерой, дальше
-- MaxDistance). cap — потолок букв надписи витрины / садка (строки у середины рамки): не шире
-- cap × capW и не выше cap × capH.
local function wordRect(gui: BillboardGui, camera: Camera, cap: number?, capW: number?, capH: number?): Rect?
	local point = gui.Parent
	if not gui.Enabled or not (point and point:IsA("Attachment")) then
		return nil
	end
	local at = point.WorldPosition
	if (at - camera.CFrame.Position).Magnitude > gui.MaxDistance then
		return nil
	end
	local screen = camera:WorldToScreenPoint(at)
	if screen.Z <= 0.05 then
		return nil
	end
	local perStud = camera.ViewportSize.Y / (2 * screen.Z * math.tan(math.rad(camera.FieldOfView) / 2))
	local size = gui.Size
	local limit = cap or math.huge
	local w: number = math.min(size.X.Scale * perStud + size.X.Offset, limit * (capW or 6))
	local h: number = math.min(size.Y.Scale * perStud + size.Y.Offset, limit * (capH or 2.2))
	return { x0 = screen.X - w / 2, y0 = screen.Y - h / 2, x1 = screen.X + w / 2, y1 = screen.Y + h / 2 }
end

local function near(r: Rect, list: { Rect }, margin: number): boolean
	for _, o in list do
		if r.x0 < o.x1 + margin and r.x1 > o.x0 - margin and r.y0 < o.y1 + margin and r.y1 > o.y0 - margin then
			return true
		end
	end
	return false
end

-- Буквы и обводка слова тают (out) или проявляются (Visible, Enabled и UIScale — у других).
local function fadeWord(gui: BillboardGui, out: boolean)
	local time = if out then CLEAR.Fade else CLEAR.Show
	local alpha = if out then 1 else 0
	for _, item in gui:GetDescendants() do
		if item:IsA("TextLabel") then
			UiFx.tween(item, time, { TextTransparency = alpha })
		elseif item:IsA("UIStroke") then
			UiFx.tween(item, time, { Transparency = alpha })
		end
	end
end

-- Одно слово: у HUD — тает, отошло на Back — проявляется; не видно — как было. cap, capW, capH —
-- как у wordRect.
local function clearWord(gui: BillboardGui?, rects: { Rect }?, cap: number?, capW: number?, capH: number?)
	local camera = Workspace.CurrentCamera
	if not gui or not camera then
		return
	end
	local r = wordRect(gui, camera, cap, capW, capH)
	if not r then
		return
	end
	local was = faded[gui] == true
	local hide = near(r, rects or hudRects(), if was then CLEAR.Back else CLEAR.Margin)
	if hide ~= was then
		faded[gui] = if hide then true else nil
		fadeWord(gui, hide)
	end
end

-- Все слова (цепочка проверок, новое уведомление).
local function clearHud()
	if not Workspace.CurrentCamera then
		return
	end
	local rects = hudRects()
	-- (ушедшие слова — из таблицы)
	for gui in faded do
		if gui.Parent == nil then
			faded[gui] = nil
		end
	end
	for _, base in bases do
		clearWord(base.sign and base.sign.gui, rects, signCap, SIGN_W, SIGN_H)
		for _, slot in base.slots do
			clearWord(slot.tag and slot.tag.gui, rects, tagCap)
			clearWord(slot.lockGui, rects)
			local steal = slot.steal
			local word = steal and steal.word
			clearWord(word and word.gui, rects, tagCap, 4, 1.4)
		end
	end
	clearWord(pier.word and pier.word.gui, rects)
	for _, gui in marketWords do
		clearWord(gui, rects)
	end
end

-- Потолки букв надписей витрин и садка — по высоте экрана (пересчёт, когда она сменилась).
local function refreshCap()
	local camera = Workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else 0
	if height <= 0 or height == tagCapHeight then
		return
	end
	tagCapHeight = height
	tagCap = TankDisplay.tagCap(height)
	signCap = TankDisplay.signCap(height)
	for _, base in bases do
		local sign = base.sign
		if sign then
			TankDisplay.capSign(sign, signCap)
		end
		for _, slot in base.slots do
			local tag = slot.tag
			if tag then
				TankDisplay.capTag(tag, tagCap)
			end
		end
		local defence = base.defence
		if defence then
			TankDisplay.capDefence(defence, signCap)
		end
	end
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
		phase = str(model, "StealPhase"),
		stealBy = num(model, "StealBy"),
		stealEnd = num(model, "StealEnd"),
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
	slot.fish, slot.uid, slot.fishId, slot.mutation, slot.rig = nil, nil, nil, nil, nil
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
	slot.rig = TankDisplay.rig(model) -- (до «вырастания»: детали в полном размере, на местах покоя)
	slot.busyUntil = 0
	local tagAt = tagPoint(slot) :: Vector3
	local tagHolder = holder("FxTankTag", CFrame.new(tagAt))
	if tagHolder then
		slot.tagHolder = tagHolder
		refreshCap()
		local tag = TankDisplay.tag(tagHolder, tagCap)
		slot.tag = tag
		updateTag(slot)
		-- (витрину крадут: надпись прохода спрятана, на её месте «КРАДУТ!»)
		tag.gui.Enabled = slot.steal == nil
		clearWord(tag.gui, nil, tagCap)
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
		-- (с места надписи витрины — она в этот миг уходит — и не выше потолка галереи)
		local text = TextUtil.fill(TEXTS.Pop, { amount = TankRules.FormatMoney(price) })
		local from = tag + Vector3.new(0, FX.RiseFrom, 0)
		riseAt(from, text, UIConfig.BillboardYellow, FX.RiseSize, FX.Rise, FX.RiseTime, DISPLAY.EventRange)
	end
end

local function dropLock(slot: Slot)
	local current = slot.lockHolder
	slot.lockHolder, slot.lockGui = nil, nil
	if current then
		current:Destroy()
	end
end

-- Закрытые витрины (Этап 5 открывает их по порядку): тусклое слово «🔒 Закрыто» — одно на
-- галерею, над первой закрытой (самый младший SlotIndex этой стороны — рядом с открытыми
-- рядами); у остальных закрытых — только табличка на тумбе и тусклая планка (сервер).
local function updateLocks(base: Base)
	local first: { [number]: Slot } = {}
	for _, slot in base.slots do
		local best = first[slot.side]
		if slot.locked and (best == nil or slot.index < best.index) then
			first[slot.side] = slot
		end
	end
	for _, slot in base.slots do
		local want = slot.locked and first[slot.side] == slot
		if want and not slot.lockHolder then
			local fishPoint = slot.fishPoint
			local at = fishPoint
				and (fishPoint.WorldCFrame * CFrame.new(0, DISPLAY.Tag.LockLift, -DISPLAY.Tag.Forward)).Position
			local point = at and holder("FxTankLock", CFrame.new(at))
			if point then
				slot.lockHolder = point
				local gui = TankDisplay.lock(point, TEXTS.SlotLocked)
				slot.lockGui = gui
				clearWord(gui)
			end
		elseif not want and slot.lockHolder then
			dropLock(slot)
		end
	end
end

--------------------------------------------------------------------------------
-- Кража витрины (Этап 4): канал StealPhase / StealEnd / StealBy
--------------------------------------------------------------------------------

local function thiefOf(userId: number?): Player?
	if not userId then
		return nil
	end
	local ok, found = pcall(function()
		return Players:GetPlayerByUserId(userId)
	end)
	return if ok then found else nil
end

-- Рыба на голове вора: центр её рамки и поворот её Body (StolenFish), иначе точка над его
-- головой (поворот nil); вора нет — nil.
local function thiefSpot(userId: number?): (Vector3?, CFrame?)
	local thief = thiefOf(userId)
	local character = thief and thief.Character
	if not character then
		return nil, nil
	end
	local carried = character:FindFirstChild("StolenFish")
	local body = carried and carried:IsA("Model") and carried.PrimaryPart
	if carried and carried:IsA("Model") and body then
		local box = carried:GetBoundingBox()
		return box.Position, body.CFrame.Rotation
	end
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.Position + Vector3.new(0, STEAL.HeadUp, 0), nil
	end
	return nil, nil
end

-- Рыба на голове вора спрятана на этом клиенте, пока к ней летит рыба витрины.
local function veil(userId: number?, hidden: boolean)
	local thief = thiefOf(userId)
	local character = thief and thief.Character
	local carried = character and character:FindFirstChild("StolenFish")
	if not carried then
		return
	end
	for _, part in carried:GetDescendants() do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

-- Сколько рыба выступает вдоль dir (мир) от своего центра при повороте turn.
local function extentAlong(rig: TankDisplay.Rig, turn: CFrame, dir: Vector3): number
	local h = rig.half
	return math.abs(turn.RightVector:Dot(dir)) * h.X
		+ math.abs(turn.UpVector:Dot(dir)) * h.Y
		+ math.abs(turn.LookVector:Dot(dir)) * h.Z
end

local function stopMoves(steal: Steal)
	for _, tween in steal.moves do
		tween:Cancel()
	end
	table.clear(steal.moves)
end

-- Надпись прохода прячется, пока витрину крадут (на её месте «КРАДУТ!»).
local function syncTag(slot: Slot)
	local tag = slot.tag
	if tag then
		tag.gui.Enabled = slot.steal == nil
	end
end

-- Рыба уходит из витрины (кража), модель не удаляется: её уносит полёт.
local function detachFish(slot: Slot): Model?
	local model = slot.fish
	stopLife(slot)
	cancelTweens(slot)
	slot.fish, slot.uid, slot.fishId, slot.mutation, slot.rig = nil, nil, nil, nil, nil
	local tagHolder = slot.tagHolder
	slot.tag, slot.tagHolder = nil, nil
	if tagHolder then
		tagHolder:Destroy()
	end
	return model
end

-- «КРАДУТ!» / «УНОСЯТ!» перед стеклом с кольцом до StealEnd и красный свет у LightBar.
local function stealLook(slot: Slot, steal: Steal, text: string, endAt: number?)
	if not steal.holder then
		local at = tagPoint(slot)
		local point = at and holder("FxTankSteal", CFrame.new(at))
		if not point then
			return
		end
		steal.holder = point
		refreshCap()
		local word = TankDisplay.stealWord(point, text, tagCap, STEAL_WORD_RANGE)
		steal.word = word
		UiFx.popIn(word.plate, { from = 0.4, time = 0.25 })
		clearWord(word.gui, nil, tagCap, 4, 1.4)
		local bar = slot.lightBar
		local glow = bar and holder("FxStealPulse", CFrame.new(bar.Position))
		if glow then
			steal.trove:Add(glow)
			TankDisplay.pulseLight(glow, BERRY.Bottom)
		end
	end
	local word = steal.word
	if not word then
		return
	end
	if word.word.Text ~= text then
		word.word.Text = text
		UiFx.punch(word.plate, { from = 0.7, peak = 1.15 })
	end
	if endAt ~= steal.ringEnd then
		steal.ringEnd = endAt
		local stop = steal.ringStop
		steal.ringStop = nil
		if stop then
			stop()
		end
		local left = if endAt then endAt - Workspace:GetServerTimeNow() else 0
		if left > 0.05 then
			steal.ringStop = UiFx.ringTimer(word.ring, left)
		end
	end
end

-- Витрину начали красть (или кража сменила фазу): запись кражи, слово, свет.
local function ensureSteal(slot: Slot, info: Info): Steal
	local steal = slot.steal
	if not steal then
		local made: Steal = {
			phase = info.phase or "hold",
			by = info.stealBy,
			trove = Trove.new(),
			word = nil,
			holder = nil,
			ringStop = nil,
			ringEnd = nil,
			rig = nil,
			moves = {},
			spot = nil,
		}
		slot.steal = made
		syncTag(slot)
		steal = made
	end
	local current = steal :: Steal
	current.by = info.stealBy or current.by
	local text = if info.phase == "carry" then WORLD_WORDS.Carrying else WORLD_WORDS.Stealing
	stealLook(slot, current, text, info.stealEnd)
	return current
end

-- Кража витрины кончилась: слово уходит (quiet — сразу), свет и твины сняты. Возвращает её
-- запись (поднятая рыба — rig — остаётся на вызывающем).
local function endSteal(slot: Slot, quiet: boolean): Steal?
	local steal = slot.steal
	if not steal then
		return nil
	end
	slot.steal = nil
	stopMoves(steal)
	local stop = steal.ringStop
	steal.ringStop = nil
	if stop then
		stop()
	end
	steal.trove:Clean()
	local point, word = steal.holder, steal.word
	steal.holder, steal.word = nil, nil
	if point then
		if quiet or not word then
			point:Destroy()
		else
			UiFx.popOut(word.plate, { time = FX.TagOut })
			task.delay(FX.TagOut + 0.05, function()
				point:Destroy()
			end)
		end
	end
	syncTag(slot)
	return steal
end

-- Удержание: рыба поднимается на Steal.Lift, наклоняется к проходу и бьётся (твины деталей).
local function lift(slot: Slot, steal: Steal)
	local model, display = slot.fish, slot.display
	if not model or not display or steal.rig then
		return
	end
	stopLife(slot)
	cancelTweens(slot)
	local found = slot.rig or TankDisplay.rig(model)
	if not found then
		return
	end
	local rig: TankDisplay.Rig = found
	steal.rig = rig
	local s = STEAL.Struggle
	local tilt = CFrame.fromAxisAngle(display.CFrame.RightVector, math.rad(-STEAL.Tilt))
	local function pose(sign: number): CFrame
		local turn = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), math.rad(sign * s.Turn)) * tilt
		return TankDisplay.around(rig, Vector3.new(0, STEAL.Lift + sign * s.Bob, 0), turn)
	end
	local from, to = pose(-1), pose(1)
	local rise = TweenInfo.new(STEAL.LiftTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	steal.moves = TankDisplay.tweenRig(rig, from, rise)
	steal.trove:Add(task.delay(STEAL.LiftTime, function()
		if rig.model.Parent == nil or slot.steal ~= steal or not rawequal(steal.rig, rig) then
			return
		end
		stopMoves(steal)
		local struggle = TweenInfo.new(s.Time, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		steal.moves = TankDisplay.tweenRig(rig, to, struggle)
	end))
end

-- Отпустили (удержание сорвалось): рыба опускается на место со всплеском «in».
local function dropBack(slot: Slot, rig: TankDisplay.Rig, loud: boolean)
	local drop = TweenInfo.new(STEAL.DropTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, tween in TankDisplay.tweenRig(rig, rig.rest, drop) do
		table.insert(slot.tweens, tween)
	end
	slot.busyUntil = os.clock() + STEAL.DropTime + 0.05
	task.delay(STEAL.DropTime, function()
		if loud and slot.fish == rig.model and rig.model.Parent then
			arrivalFx(slot, true)
		end
	end)
end

type Leg = {
	at: () -> (Vector3, CFrame),
	time: number,
	style: Enum.EasingStyle,
	direction: Enum.EasingDirection,
}

-- Полёт рыбы по отрезкам (их точка и поворот считаются в начале отрезка: вор идёт); done — в
-- конце или когда рыбу убрали (с базой).
local function fly(rig: TankDisplay.Rig, legs: { Leg }, done: () -> ())
	local index = 0
	local function nextLeg()
		index += 1
		local leg = legs[index]
		if not leg or rig.model.Parent == nil then
			done()
			return
		end
		local centre, turn = leg.at()
		local info = TweenInfo.new(leg.time, leg.style, leg.direction)
		TankDisplay.tweenRig(rig, TankDisplay.bodyAt(rig, centre, turn), info)
		task.delay(leg.time, nextLeg)
	end
	nextLeg()
end

-- Перед стеклом витрины, куда рыба вылетает СКВОЗЬ ПЕРЕДНЮЮ грань (вся рыба — снаружи), на
-- высоте from (мир), и вершина дуги над серединой пути к to (верх рыбы не выше FishPoint + ArcTop).
local function arcPoints(slot: Slot, rig: TankDisplay.Rig, turn: CFrame, fromY: number): (Vector3, (Vector3) -> Vector3)
	local frame = (slot.fishPoint :: Attachment).WorldCFrame
	local front = frame.LookVector
	local face = if slot.display then slot.display.Size.Z / 2 else 3.1
	local reach = face + extentAlong(rig, turn, front) + STEAL.ArcOut
	local out = Vector3.new(frame.Position.X, fromY, frame.Position.Z) + front * reach
	local top = frame.Position.Y + STEAL.ArcTop - extentAlong(rig, turn, Vector3.new(0, 1, 0))
	local function apex(to: Vector3): Vector3
		local mid = out:Lerp(to, 0.5)
		return Vector3.new(mid.X, math.max(top, out.Y), mid.Z)
	end
	return out, apex
end

-- Рыба витрины вылетает к вору на голову (там её сменяет StolenFish), потом удаляется. Модель
-- уже не в витрине (detachFish); пока летит — среди уходящих рыб базы.
local function arcOut(base: Base, slot: Slot, model: Model, rig: TankDisplay.Rig, thiefId: number?)
	if not slot.fishPoint then
		model:Destroy()
		return
	end
	base.leaving[model] = true
	local current = rig.body.CFrame
	local start = TankDisplay.centreAt(rig, current)
	local turn0 = current.Rotation
	local out, apex = arcPoints(slot, rig, turn0, start.Y + 0.4)
	local frame = (slot.fishPoint :: Attachment).WorldCFrame
	local target, turnEnd = thiefSpot(thiefId)
	local aim: Vector3 = target or (out + frame.LookVector * 2)
	local turned: CFrame = turnEnd or turn0
	local function follow(): (Vector3, CFrame)
		local c, r = thiefSpot(thiefId)
		aim = c or aim
		turned = r or turned
		return aim, turned
	end
	local t = STEAL.ArcTime
	veil(thiefId, true)
	fly(rig, {
		{
			at = function()
				return out, turn0
			end,
			time = t * 0.3,
			style = Enum.EasingStyle.Quad,
			direction = Enum.EasingDirection.Out,
		},
		{
			at = function()
				local c, r = follow()
				return apex(c), turn0:Lerp(r, 0.5)
			end,
			time = t * 0.3,
			style = Enum.EasingStyle.Quad,
			direction = Enum.EasingDirection.Out,
		},
		{
			at = follow,
			time = t * 0.4,
			style = Enum.EasingStyle.Quad,
			direction = Enum.EasingDirection.In,
		},
	}, function()
		veil(thiefId, false)
		base.leaving[model] = nil
		model:Destroy()
	end)
end

-- Рыбу вернули (вынос сорвался): новая рыба витрины вылетает с головы вора (или с места, где
-- его видели последним) и падает в витрину со всплеском «in». Далеко или уже летит
-- Steal.MaxArcs копий — просто появляется.
local function arcBack(base: Base, slot: Slot, steal: Steal, loud: boolean)
	showFish(base, slot, false, 0)
	local model, point = slot.fish, slot.fishPoint
	if not model or not point then
		return
	end
	local rig = if loud and arcs < STEAL.MaxArcs then TankDisplay.rig(model) else nil
	if not rig then
		if loud then
			arrivalFx(slot, true)
		end
		return
	end
	arcs += 1
	local tag = slot.tag
	if tag then
		tag.gui.Enabled = false
	end
	slot.busyUntil = os.clock() + STEAL.ArcTime + 0.1
	local rest = rig.rest.Rotation
	local home = TankDisplay.centreAt(rig, rig.rest)
	local out, apex = arcPoints(slot, rig, rest, home.Y + 0.4)
	local c, r = thiefSpot(steal.by)
	local start: Vector3 = c or steal.spot or (out + point.WorldCFrame.LookVector * 2)
	local turn0: CFrame = r or rest
	TankDisplay.setRig(rig, TankDisplay.bodyAt(rig, start, turn0))
	local t = STEAL.ArcTime
	fly(rig, {
		{
			at = function()
				return apex(start), turn0:Lerp(rest, 0.5)
			end,
			time = t * 0.4,
			style = Enum.EasingStyle.Quad,
			direction = Enum.EasingDirection.Out,
		},
		{
			at = function()
				return out, rest
			end,
			time = t * 0.3,
			style = Enum.EasingStyle.Quad,
			direction = Enum.EasingDirection.In,
		},
		{
			at = function()
				return home, rest
			end,
			time = t * 0.3,
			style = Enum.EasingStyle.Quad,
			direction = Enum.EasingDirection.Out,
		},
	}, function()
		arcs -= 1
		if slot.fish == model and model.Parent then
			TankDisplay.setRig(rig, rig.rest)
			arrivalFx(slot, true)
			local shown = slot.tag
			if shown then
				shown.gui.Enabled = slot.steal == nil
				UiFx.popIn(shown.plate, { from = 0 })
			end
		end
	end)
end

-- Event "stolen|<вор>": «УКРАДЕНО!» всплывает и тает, красные искры летят к вору; рыба, которая
-- ещё в витрине (вынос не видели; Carry.Enabled = false — рыба переходит в конце удержания),
-- прыгает к нему.
local function stolenFx(base: Base, slot: Slot, thiefId: number?, loud: boolean)
	local steal = endSteal(slot, true)
	if loud then
		local at = tagPoint(slot)
		if at then
			riseAt(at, WORLD_WORDS.Stolen, BERRY, STEAL.Word, STEAL.StolenRise, STEAL.StolenTime, STEAL_WORD_RANGE)
		end
		local top = topOf(slot)
		if top then
			local spot = thiefSpot(thiefId)
			local colors = { Color3.new(1, 1, 1), BERRY.Top, BERRY.Bottom }
			burst(top, "sparkle", colors, STEAL.Sparks, if spot then spot - top else nil)
		end
	end
	local model = slot.fish
	if model then
		local rig = (steal and steal.rig) or slot.rig or TankDisplay.rig(model)
		detachFish(slot)
		if loud and rig then
			arcOut(base, slot, model, rig, thiefId)
		else
			model:Destroy()
		end
	end
end

-- Перечитать витрину (после её Event / State / StealPhase или при постройке базы).
local function refresh(base: Base, slot: Slot)
	local info = readSlot(slot.model)
	local event = info.event
	local kind, detail = nil, nil
	if event ~= nil and event ~= slot.lastEvent then
		kind, detail = parseEvent(event)
	end
	slot.lastEvent = event
	local near = base.distance <= DISPLAY.EventRange
	local loud = kind ~= nil and kind ~= "mount" and near
	local fishId = info.fishId
	local wanted = info.state == "fish" and fishId ~= nil and TankDisplay.template(fishId, info.mutation) ~= nil
	local same = wanted
		and slot.fish ~= nil
		and slot.uid == info.uid
		and slot.fishId == info.fishId
		and slot.mutation == info.mutation
	slot.info = if wanted then info else nil
	local locked = info.state == "locked"
	if locked ~= slot.locked then
		slot.locked = locked
		updateLocks(base)
	end
	-- Этап 4: кража витрины (StealPhase пишется последним; рыба остаётся в данных хозяина до
	-- самого конца выноса)
	local phase = if info.state == "fish" then info.phase else nil
	local current = slot.steal
	local prev = if current then current.phase else nil
	if kind == "stolen" then
		stolenFx(base, slot, tonumber(detail), loud)
		prev, same = nil, false
	end
	if phase == "carry" then
		-- рыба на голове вора: в витрине её нет
		local steal = ensureSteal(slot, info)
		local model = slot.fish
		if model then
			local rig = steal.rig or slot.rig or TankDisplay.rig(model)
			stopMoves(steal)
			steal.rig = nil
			detachFish(slot)
			if prev == "hold" and near and rig then
				arcOut(base, slot, model, rig, info.stealBy)
			else
				model:Destroy()
			end
		end
		steal.phase = "carry"
		steal.spot = thiefSpot(info.stealBy) or steal.spot
		slot.queued = false
		return
	end
	if phase == "hold" and wanted then
		local steal = ensureSteal(slot, info)
		steal.phase = "hold"
		if same then
			updateTag(slot)
		else
			if slot.fish then
				dropFish(base, slot, false)
			end
			steal.rig = nil
			slot.queued = false
			showFish(base, slot, false, 0)
		end
		lift(slot, steal)
		return
	end
	if prev ~= nil then
		local ended = endSteal(slot, false)
		local rig = ended and ended.rig
		if prev == "hold" and same and rig and slot.fish == rig.model then
			dropBack(slot, rig, near)
			updateTag(slot)
			return
		end
		if prev == "carry" and wanted and slot.fish == nil and ended then
			slot.queued = false
			arcBack(base, slot, ended, near)
			return
		end
	end
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

-- Строка защит надписи садка: («🛡️ 0:42» | nil, «🔐1 · 🐕 · 🚨» | nil).
local function defenceTexts(model: Model): (string?, string?)
	local now = Workspace:GetServerTimeNow()
	local untilAt = num(model, "ProtectUntil")
	local protect = if untilAt and untilAt > now
		then TextUtil.fill(DEFENCE_WORDS.Protect, { t = StealRules.FormatClock(untilAt - now) })
		else nil
	local parts: { string } = {}
	local lock = num(model, "LockLevel")
	if lock and lock >= 1 then
		table.insert(parts, TextUtil.fill(DEFENCE_WORDS.Lock, { n = math.min(math.floor(lock), LOCK_LEVELS) }))
	end
	if model:GetAttribute("HasDog") == true then
		table.insert(parts, DEFENCE_WORDS.Dog)
	end
	if model:GetAttribute("HasAlarm") == true then
		table.insert(parts, DEFENCE_WORDS.Alarm)
	end
	local owned = if #parts > 0 then table.concat(parts, DEFENCE_WORDS.Separator) else nil
	if protect and owned then
		-- (рядом с «🛡️ 0:42»: «· 🔐1 · 🐕»)
		owned = string.gsub(DEFENCE_WORDS.Separator, "^%s+", "") .. owned
	end
	return protect, owned
end

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
			refreshCap()
			local sign = TankDisplay.sign(point, signCap)
			base.sign = sign
			clearWord(sign.gui, nil, signCap, SIGN_W, SIGN_H)
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
		-- Этап 4: третья строка — защита базы «🛡️ 0:42» (любая; готов ли щит — никогда) и
		-- купленные защиты «🔐1 · 🐕 · 🚨» (видят все)
		local protect, owned = defenceTexts(base.model)
		local row = base.defence
		if (protect or owned) and not row then
			row = TankDisplay.signDefence(sign, signCap)
			base.defence = row
		end
		if row then
			TankDisplay.setSignDefence(sign, row, protect, owned)
		end
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
		defence = nil,
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
		-- галерея: по какую сторону двора от большого аквариума (знак X в его осях)
		local across = if display and display:IsA("BasePart")
			then glass.CFrame:PointToObjectSpace(display.Position).X
			else 0
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
			locked = false,
			side = if across < 0 then -1 else 1,
			lockHolder = nil,
			lockGui = nil,
			lastEvent = nil,
			pending = false,
			queued = false,
			steal = nil,
			rig = nil,
		}
		table.insert(base.slots, slot)
		base.trove:Connect(slotModel.AttributeChanged, function(name: string)
			-- (Этап 4: канал кражи StealPhase пишется последним — по нему и перечитываем)
			if name == "Event" or name == "State" or name == "StealPhase" then
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
		elseif SIGN_ATTRIBUTES[name] then
			updateSign(base) -- (Этап 4: строка защит)
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
			endSteal(slot, true)
			dropFish(base, slot, false)
			dropLock(slot)
			slot.info, slot.queued, slot.locked = nil, false, false
		end
		for leaving in base.leaving do
			leaving:Destroy()
		end
		table.clear(base.leaving)
		base.sign = nil
		base.defence = nil
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
	-- Этап 4: у своей базы кража — «🚨 КРАДУТ!» видно и в поклёвку, и в мини-игре (не под
	-- карточкой улова и не под своим трофеем: там его табличка)
	local own = pier.base
	local alarm = own ~= nil and own:GetAttribute("AlarmState") == "theft"
	local busy = (not alarm and state ~= nil and BUSY_STATES[state] == true)
		or (hud ~= nil and hud:GetAttribute("CounterHold") ~= nil)
		or pier.heldFish
	local show = slots ~= nil and not busy
	if alarm ~= pier.alarm then
		pier.alarm = alarm
		local label = pier.alarmLabel
		if alarm and not label then
			label = TankDisplay.pierAlarm(word, WORLD_WORDS.Pier)
			pier.alarmLabel = label
		end
		local stop = pier.alarmStop
		pier.alarmStop = nil
		if stop then
			stop()
		end
		word.top.Visible = not alarm
		word.bottom.Visible = not alarm
		if label then
			label.Visible = alarm
			if alarm then
				pier.alarmStop = UiFx.pulse(label, STEAL.PierPulse, STEAL.PulsePeriod)
			end
		end
		if alarm and show and pier.visible then
			UiFx.punch(word.plate, { from = 0.6, peak = 1.2 })
		end
	end
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
		clearWord(word.gui) -- (уведомление на его месте — сразу тает, не мелькает)
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
	local stop = pier.alarmStop
	pier.base, pier.alarm, pier.alarmLabel, pier.alarmStop = nil, false, nil, nil
	if stop then
		stop()
	end
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
	-- Этап 4: кража у своей базы (AlarmState пишет StealService)
	if base and base:IsA("Model") then
		pier.base = base
		pier.trove:Connect(base.AttributeChanged, function(name: string)
			if name == "AlarmState" then
				refreshPier()
			end
		end)
	end
	refreshPier()
end

local function watchCharacter(character: Model?)
	pier.characterTrove:Clean()
	pier.heldFish = false
	if not character then
		refreshPier()
		return
	end
	-- (трофей убран — слово ждёт ещё Pier.TrophyGap: его табличка тает там же)
	local function update()
		local held = character:FindFirstChild("HeldFish") ~= nil
		pier.heldGen += 1
		if held then
			if not pier.heldFish then
				pier.heldFish = true
				refreshPier()
			end
		elseif pier.heldFish then
			local gen = pier.heldGen
			task.delay(PIER.TrophyGap, function()
				if pier.heldGen == gen and pier.heldFish then
					pier.heldFish = false
					refreshPier()
				end
			end)
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
				table.insert(marketWords, TankDisplay.market(word, TextUtil.fill(TEXTS.MarketWord, { bonus = bonus })))
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
	refreshCap()
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
			local steal = slot.steal
			if steal and steal.phase == "carry" then
				steal.spot = thiefSpot(steal.by) or steal.spot
			end
			local model, point = slot.fish, slot.fishPoint
			if model and point and not steal then
				-- с запасом: оживает ближе LifeRange, замирает только дальше LifeDrop
				local d = distanceFrom(point.WorldPosition, cam, body)
				if slot.life then
					if not lifeEnabled or d > DISPLAY.LifeDrop then
						stopLife(slot)
					end
				elseif lifeEnabled and d <= DISPLAY.LifeRange and now >= slot.busyUntil then
					cancelTweens(slot)
					slot.life = TankDisplay.startLife(model, rng)
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
		-- Этап 4: «🛡️ 0:42» на надписи садка идёт раз в TagEvery с
		if tagTime and base.sign and num(base.model, "ProtectUntil") then
			updateSign(base)
		end
	end
	lastBuilds = built
	-- доход над ведром
	if now >= pier.nextPop then
		pier.nextPop = now + PIER.PopEvery
		popIncome()
	end
	-- слова не под HUD
	clearHud()
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

function TankWorldController.Lock(base: Instance, index: number): BillboardGui?
	local slot = slotOf(base, index)
	return slot and slot.lockGui
end

function TankWorldController.IsFaded(gui: BillboardGui): boolean
	return faded[gui] == true
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
	local fadedCount = 0
	for gui in faded do
		fadedCount += if gui.Parent then 1 else 0
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
		faded = fadedCount,
		tagCap = tagCap,
		signCap = signCap,
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
	-- новое уведомление: слова под ним тают, как только оно въехало (не ждать цепочку проверок)
	local toasts = hud:FindFirstChild("Toasts")
	if toasts then
		toasts.ChildAdded:Connect(function(child: Instance)
			if child.Name == "Toast" then
				task.delay(CLEAR.ToastWait, clearHud)
			end
		end)
	end
	Net.Event("FishingState").OnClientEvent:Connect(onFishingState)
	Net.Event("TankEvent").OnClientEvent:Connect(onTankEvent)
	setupMarket()
	setupPier()
	task.defer(loop)
end

return TankWorldController
