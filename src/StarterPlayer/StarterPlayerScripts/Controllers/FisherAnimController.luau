--!strict
--[[
	FisherAnimController — тело рыбака двигается: замах и бросок, ожидание, поклёвка, подсечка,
	борьба с рыбой, улов над головой, «сорвалась». Только на клиенте, для ВСЕХ рыбаков рядом
	(и для себя): каждый клиент сам анимирует каждого рыбака не дальше RANGE studs по данным,
	которые и так видят все (атрибуты Player FishingState, CastTime, BobberTarget, FishFx —
	шапка RemoteNames; модель HeldFish и удочка-Tool в персонаже; поплавок FishingFxController).

	Техника (см. FisherRig): процедурный слой поверх обычной анимации Roblox — каждый кадр
	в RunService.PreSimulation пишем joint.Transform (R15 Motor6D, R15 AnimationConstraint, R6).
	Animator перед этим кладёт свою позу (idle / walk / «toolnone» — рука с удочкой вперёд),
	мы смешиваемся с ней по весу; перестали писать — обычная анимация возвращается сама.
	Transform не реплицируется, поэтому у каждого клиента своя копия движения всех рыбаков.
	НЕ используем (и не пробуйте): KeyframeSequenceProvider / AnimationClipProvider Register*
	(временные id работают только в Studio, в живой игре — ошибка), Animation Graph и
	загруженные анимации (нужны опубликованные ассеты), твины C0/C1 (на AnimationConstraint-
	ригах C0 только для чтения — ошибка), правку RigAttachment (ломает ретаргетинг), запись в
	RenderStepped (Animator её перетирает). Запасной вариант, если процедурный слой однажды
	сломается: StringValue «toolanim» = "Slash" в удочке своего игрока — стандартный Animate
	сыграет свой взмах (реплицируется, но без синхронизации с поплавком). Выключатель —
	FisherAnimController.Enabled = false (или атрибут FisherAnimOff у LocalPlayer). Если
	новый Avatar Joint Upgrade начнёт вести себя странно: Studio → Game Settings → Avatar →
	AvatarJointUpgrade = Disabled (временно; в файле места это не сохраняется).

	Позы и тайминги — FisherPoses; переходы — плавные (CFrame:Lerp каждого сустава от
	«снимка» текущей позы, с плавностью), ничего не «щёлкает», даже если событие оборвало
	движение на середине. Мультяшно и крупно — на телефоне рыбак ≈ 20 px на stud: подскоки
	таза 0,2–0,55 stud, рывки рук 15–25°, качания вбок; удочка в руке ПРАВЕЕ поплавка — из-за
	спины видны вся удочка, её изгиб и леска. Фазы (mode):
	  Ready   — взял удочку: поднял, глянул на кончик, опустил (Hold);
	  Hold    — удочка в руке между забросами: лёгкое покачивание ещё FisherPoses.Timing.Linger с,
	            потом слой отпускается (обычная анимация);
	  Cast    — замах «сбоку на три четверти» (удочка вверх-вправо, корпус довёрнут; свой — сразу
	            по нажатию: Cue("castPress"); чужой — когда пришло "Waiting"), «взведён» с дрожью,
	            бросок ровно к CastTime (сервер ставит CastTime на FishingConfig.CastWindUp позже
	            заброса — поплавок срывается с кончика как раз в миг броска, у всех клиентов),
	            проводка держится, пока поплавок летит (до приводнения), успокоение → Wait;
	  Wait    — ждём: покачивание, дыхание, взгляд на поплавок; «примерка» рыбы и нырки
	            поплавка (FishingFxController.GetBobberDip) дёргают кончик удочки; раз в
	            FisherPoses.Timing.Fidget с — «живое» движение (переступил, дёрнул удочкой,
	            огляделся, притопнул);
	  Bite    — вздрогнул (подскок, плечи вверх), присел и завалился к удочке, дрожит, кончик и
	            сам рыбак дёргаются с поплавком;
	  Strike  — подсечка с подскоком (свой — по нажатию, Cue("hookPress"); чужой — Bite →
	            Reeling) → Reel;
	  Reel    — борьба: глубоко присел и откинулся, левая рука крутит катушку, удочку ведёт за
	            метаниями поплавка (FishingFxController: тот же ReelSpeed и фаза), рыбака
	            дёргает вбок, удочка хлещет вбок (FisherRod), дрожь натяжения; своя — сильнее
	            у редкой рыбы; попадание в мини-игре — рывок удочкой сразу по нажатию
	            (FishingController: Cue("tapHit"), победное — "tapWin"; "Zone" сервера — только
	            если рывка по нажатию не было), нажал мимо — удочка клюнула ("tapMiss");
	  Caught  — FishFx caught: рывок (эпическая и выше — с подскоком), взгляд вверх за прыжком
	            рыбы, к концу прыжка обе руки вверх, рыба приземлилась (HeldFish) — присел под
	            её весом, подпрыгнул, «качание» руками (легендарная / мифическая — ещё оборот на
	            месте с рыбой и больше качаний) → Trophy;
	  Trophy  — пока HeldFish над головой: держит её обеими руками (удочка смотрит вперёд над
	            водой), дышит, колени пружинят; раз в Timing.Trophy.ShowEvery с «показ» — рывок
	            руками вместе со шлепком рыбы (FishingFxController.KickHeldFish) и поворот с ней
	            влево-вправо; повтор трофея своего игрока (FishingFxController.TrophyReplayed) —
	            настоящий праздник (присел, два прыжка, три качания, поворот); рыба исчезла —
	            руки вниз → Hold;
	  Lost    — FishFx lost: поник (плечи и голова вниз, присел, удочка вправо-вниз, левая рука
	            повисла), топнул, качает головой, выпрямился → Hold;
	  Retract — "Idle" без улова / потери: крутит катушку, сматывая леску → Hold.
	Активная рыбалка важнее трофея: забросил с рыбой над головой — руки ловят, а после
	"Idle" (рыба ещё над головой) снова держат её.
	Корпус разворачивается к поплавку (BobberTarget, не больше YAW_LIMIT°: пополам таз и
	талия), голова смотрит на поплавок (плавно, в пределах). Персонаж идёт или в воздухе —
	корпус и голова сразу отдаются обычной анимации (нет «подпрыгиваний» AJU-ригов при ходьбе),
	руки — наполовину (с рыбой над головой — держат её: «несёт трофей»); умер или сидит — слоя нет.

	Удочка гнётся (FisherRod): к леске под нагрузкой (поклёвка, борьба, подсечка), хлещет при
	броске и распрямляется с отскоком, когда леска ослабла; кончик (Handle.TipAttachment —
	из него выходит леска FishingFxController) идёт за изгибом.

	Бюджет: одно соединение PreSimulation на всех, только пока кого-то анимируем (рыбачит,
	держит рыбу, доигрывает короткое движение) и он не дальше RANGE studs от своего персонажа
	(без персонажа — от камеры); остальные отпущены. Дальний рыбак проверяется таймером раз
	в POLL секунд, только пока такой есть; его слои и импульсы не копятся (у неанимируемого
	список слоёв — одна текущая фаза, импульсов нет). Ни одного Instance в кадре; ≈15 записей
	Transform и ≤14 C0 удочки на рыбака (удочка дальше ROD_NEAR studs не гнётся, неизменный
	изгиб не переписывается). Торс, голова и BobberTarget — из кэша, поплавок ищется раз за кадр.
	Подписки на игрока / персонажа убираются вместе с ним.

	API (для FishingController, будущих эффектов и тестов):
	  FisherAnimController.Cue(name: string) -> ()
	      -- свои предсказанные события (без ожидания сервера): "castPress" — нажал «Забросить»
	      -- (замах сразу; нет ответа CastTimeout с — опускает), "hookPress" — нажал «Подсечь»,
	      -- "castCancel" — заброс не принят, "tapHit" — попал в мини-игре (предсказание
	      -- FishingController; "Zone" сервера на него уже не дёргает), "tapWin" — победное
	      -- нажатие (рывок сильнее), "tapMiss" — нажал мимо зоны.
	  FisherAnimController.PhaseChanged -- Signal: (player: Player, phase: string) — фаза
	      -- движения рыбака сменилась (имена — список выше; ещё "Release" — миг броска, поплавок
	      -- срывается с кончика; "Landed" — пойманная рыба приземлилась над головой; "None" —
	      -- слой отпущен). Для эффектов следующих волн (рыба над головой, тень, леска).
	  FisherAnimController.GetPhase(player) -> (string, number) -- фаза и os.clock() её начала
	  FisherAnimController.IsAnimating(player) -> boolean       -- слой сейчас пишет суставы
	  FisherAnimController.GetRodBend(player) -> number         -- изгиб удочки у кончика, рад
	  FisherAnimController.GetRodTip(player) -> Attachment?     -- кончик удочки в руке
	  FisherAnimController.GetDebug(player) -> { layers, pulses, fidgets }? -- для тестов
	  FisherAnimController.Enabled: boolean                     -- выключатель (true)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local FishingConfig = require(Config:WaitForChild("FishingConfig"))
local Net = require(Shared:WaitForChild("Net"))
local Util = Shared:WaitForChild("Util")
local Signal = require(Util:WaitForChild("Signal"))
local Trove = require(Util:WaitForChild("Trove"))
local FisherRig = require(script.Parent:WaitForChild("FisherRig"))
local FisherPoses = require(script.Parent:WaitForChild("FisherPoses"))
local FisherRod = require(script.Parent:WaitForChild("FisherRod"))

local RANGE = 150 -- дальше от своего персонажа (камеры) рыбаков не анимируем, studs
local POLL = 0.5 -- как часто проверять дальних / ещё не загрузившихся рыбаков, с
local ALIVE_CHECK = 0.5 -- как часто проверять, не заменили ли суставы (внешность, смерть), с
local MOVE_SPEED = 2.5 -- быстрее (studs/с по горизонтали) — «идёт»
local AIR_SPEED = 6 -- быстрее по вертикали — «в воздухе»
local GROUP_TIME = 0.15 -- веса групп (руки / корпус / голова) меняются за столько, с
local LAYER_TIME = 0.2 -- добавочные движения фазы появляются / гаснут за столько, с
local YAW_LIMIT = 60 -- разворот к поплавку, не больше, °
local YAW_TIME = 0.25
local LOOK_YAW, LOOK_UP, LOOK_DOWN = 45, 20, 35 -- взгляд на поплавок: пределы, °
local LOOK_TIME = 0.12
local SPEED_TIME = 0.1
local EVENT_GRACE = 0.6 -- "Idle" через столько после FishFx — конец той же рыбалки (не «сматываем»)
local REEL_SPEED = 7.5 -- = FishingFxController FX.ReelSpeed: метания поплавка, рад/с
local CRANK_HZ = 2.2 -- катушка в борьбе, оборотов в секунду
local RETRACT_CRANK_HZ = 4
-- Сила движений борьбы по редкости своей рыбы (у чужих редкость неизвестна до улова).
local INTENSITY: { [string]: number } = { Common = 1, Rare = 1.1, Epic = 1.25, Legendary = 1.4, Mythic = 1.6 }
local OTHER_INTENSITY = 1.2
local RARE_CATCH: { [string]: boolean } = { Legendary = true, Mythic = true }
local BIG_CATCH: { [string]: boolean } = { Epic = true, Legendary = true, Mythic = true }
local EPIC_INTENSITY = INTENSITY.Epic -- своя рыба не слабее: удочка гнётся сильнее (FisherRod)
local EPIC_BEND = 0.8 -- рад, предел изгиба тогда (обычный — FisherRod MAX_BEND)
local ROD_NEAR = 60 -- дальше удочку не гнём (изгиб — пара пикселей), studs
local DEG = math.pi / 180

local T = FisherPoses.Timing
local rot = FisherRig.rot
local IDENTITY = CFrame.identity

type PoseData = { cf: { [string]: CFrame }, w: { [string]: number } }
type Ease = (number) -> number
type Key = { at: number, pose: PoseData, ease: Ease }
type Add = { [string]: CFrame }
type Pulse = { at: number, duration: number, kind: string, amount: number }
type Layer = { mode: string, w: number, target: number }

type Fisher = {
	player: Player,
	own: boolean,
	seed: number,
	trove: Trove.Trove,
	charTrove: Trove.Trove,
	character: Model?,
	humanoid: Humanoid?,
	root: BasePart?,
	rig: FisherRig.Rig?,
	nextAlive: number,
	tool: Tool?,
	rod: FisherRod.Rod?,
	heldFish: Instance?,
	state: string, -- атрибут FishingState
	fxValue: any, -- последнее увиденное значение FishFx
	fxAt: number, -- os.clock() последнего события FishFx
	mode: string,
	modeSince: number,
	modeEnd: number?, -- когда фаза сменится сама (дорожка уже ведёт к позе следующей)
	nextMode: string?,
	keys: { Key },
	last: PoseData, -- поза прошлого кадра (для «снимка» на переходе)
	layers: { Layer },
	pulses: { Pulse },
	castAt: number?, -- os.clock(): начало замаха
	windAt: number?, -- … замах дойдёт до WindUp
	releaseAt: number?, -- os.clock() броска (CastTime)
	released: boolean, -- "Release" уже объявлен
	caughtAt: number,
	landed: boolean,
	rarity: string?,
	lingerUntil: number,
	active: boolean,
	master: number,
	masterTarget: number,
	arms: number,
	torso: number,
	head: number,
	lastPosition: Vector3?,
	speed: number,
	vy: number,
	yaw: number,
	lookPitch: number,
	lookYaw: number,
	lookW: number,
	lookTarget: Vector3?, -- куда смотрел (взгляд гаснет к ней плавно)
	loadPulseUntil: number,
	water: Vector3?, -- атрибут BobberTarget (кэш: читается в AttributeChanged, не каждый кадр)
	torsoPart: BasePart?, -- UpperTorso / Torso и Head (кэш, проверяется по Parent)
	headPart: BasePart?,
	tapAt: number, -- os.clock() последнего рывка удочкой в мини-игре (предсказанного или "Zone")
	nextFidget: number, -- ожидание: когда следующее «живое» движение
	fidgetAt: number,
	fidgetKind: number, -- 0 — нет; 1 переступил, 2 дёрнул удочкой, 3 огляделся, 4 притопнул
	fidgets: number,
	nextShow: number, -- трофей: когда следующий «показ» рыбы
}

local FisherAnimController = {
	Enabled = true,
	-- (player: Player, phase: string) — см. шапку.
	PhaseChanged = Signal.new(),
}

local fishers: { [Player]: Fisher } = {}
local active: { [Fisher]: true } = {}
local connection: RBXScriptConnection? = nil
local polling = false
local fx: any = nil -- FishingFxController (GetBobber, GetBobberDip, TrophyReplayed)

--------------------------------------------------------------------------------
-- Позы и плавность
--------------------------------------------------------------------------------

local POSES: { [string]: PoseData } = {}
for name, data in FisherPoses.Poses :: { [string]: { [string]: { number } } } do
	local cf, w = {}, {}
	for channel, a in data do
		local r = rot(a[1], a[2], a[3])
		if a[4] then
			r = CFrame.new(a[4], a[5], a[6]) * r
		end
		cf[channel] = r
		w[channel] = 1
	end
	POSES[name] = { cf = cf, w = w }
end
local EMPTY: PoseData = { cf = {}, w = {} }

local function linear(u: number): number
	return u
end
local function outQuad(u: number): number
	return 1 - (1 - u) * (1 - u)
end
local function inCubic(u: number): number
	return u * u * u
end
local function outBack(u: number): number
	local c1 = 1.70158
	return 1 + (c1 + 1) * (u - 1) ^ 3 + c1 * (u - 1) ^ 2
end
local function inOutSine(u: number): number
	return -(math.cos(math.pi * u) - 1) / 2
end

local GROUP: { [string]: string } = {
	RShoulder = "arms",
	RElbow = "arms",
	RWrist = "arms",
	LShoulder = "arms",
	LElbow = "arms",
	LWrist = "arms",
	Neck = "head",
	Root = "torso",
	Waist = "torso",
	RHip = "torso",
	LHip = "torso",
	RKnee = "torso",
	LKnee = "torso",
	RAnkle = "torso",
	LAnkle = "torso",
}

-- Фазы самой рыбалки (важнее трофея; корпус к поплавку).
local FISHING: { [string]: boolean } = {
	Cast = true,
	Wait = true,
	Bite = true,
	Strike = true,
	Reel = true,
	Retract = true,
	Caught = true,
	Lost = true,
}
-- Насколько голова смотрит на поплавок в фазе.
local LOOK: { [string]: number } = { Cast = 0.5, Wait = 1, Bite = 1, Strike = 0.6, Reel = 0.8, Retract = 0.7 }

local function clone(pose: PoseData): PoseData
	return { cf = table.clone(pose.cf), w = table.clone(pose.w) }
end

local function key(at: number, pose: PoseData, ease: Ease?): Key
	return { at = at, pose = pose, ease = ease or linear }
end

-- Поза дорожки в момент now (между ключами — смешение с плавностью ключа-цели) → out.
local function evaluate(keys: { Key }, now: number, out: PoseData)
	table.clear(out.cf)
	table.clear(out.w)
	local count = #keys
	if count == 0 then
		return
	end
	local index = 1
	while index < count and keys[index + 1].at <= now do
		index += 1
	end
	local a = keys[index]
	if index == count or now <= a.at then
		for channel, cf in a.pose.cf do
			out.cf[channel] = cf
			out.w[channel] = a.pose.w[channel] or 1
		end
		return
	end
	local b = keys[index + 1]
	local span = b.at - a.at
	local e = b.ease(if span > 0 then math.clamp((now - a.at) / span, 0, 1) else 1)
	local ew = math.clamp(e, 0, 1)
	for channel, cfa in a.pose.cf do
		local wa = a.pose.w[channel] or 1
		local cfb = b.pose.cf[channel]
		if cfb then
			out.cf[channel] = cfa:Lerp(cfb, e)
			out.w[channel] = wa + ((b.pose.w[channel] or 1) - wa) * ew
		else
			out.cf[channel] = cfa
			out.w[channel] = wa * (1 - ew)
		end
	end
	for channel, cfb in b.pose.cf do
		if a.pose.cf[channel] == nil then
			out.cf[channel] = cfb
			out.w[channel] = (b.pose.w[channel] or 1) * ew
		end
	end
end

--------------------------------------------------------------------------------
-- Добавки: качания, дрожь, импульсы (всё — повороты в пространстве «торса»)
--------------------------------------------------------------------------------

local function addRot(add: Add, channel: string, x: number, y: number, z: number)
	add[channel] = rot(x, y, z) * (add[channel] or IDENTITY)
end

local function addMove(add: Add, channel: string, dx: number, dy: number, dz: number)
	add[channel] = CFrame.new(dx, dy, dz) * (add[channel] or IDENTITY)
end

local function wave(now: number, hz: number, phase: number?): number
	return math.sin(2 * math.pi * hz * now + (phase or 0))
end

-- Огибающая «вверх за attack, вниз к концу» (0..1).
local function envelope(u: number, attack: number): number
	if u <= 0 or u >= 1 then
		return 0
	end
	if u < attack then
		return math.sin(u / attack * math.pi / 2)
	end
	return 0.5 + 0.5 * math.cos((u - attack) / (1 - attack) * math.pi)
end

local function smoothstep(a: number, b: number, x: number): number
	local u = math.clamp((x - a) / (b - a), 0, 1)
	return u * u * (3 - 2 * u)
end

local function dipOf(f: Fisher): number
	if fx and type(fx.GetBobberDip) == "function" then
		local ok, dip = pcall(fx.GetBobberDip, f.player)
		if ok and type(dip) == "number" then
			return math.clamp(dip, 0, 1)
		end
	end
	return 0
end

local function intensity(f: Fisher): number
	if not f.own then
		return OTHER_INTENSITY
	end
	return INTENSITY[f.rarity or "Common"] or 1
end

-- Импульс — короткая добавка поверх (PULSE[kind], amount — масштаб); только у тех, кого сейчас
-- анимируем: у дальних (не active) список не растёт — их некому разбирать покадрово.
local function pulse(f: Fisher, kind: string, duration: number, amount: number?, delay: number?)
	if not f.active then
		return
	end
	table.insert(f.pulses, { at = os.clock() + (delay or 0), duration = duration, kind = kind, amount = amount or 1 })
end

-- Число 0..1 по зерну рыбака и номеру (паузы между «живыми» движениями — у каждого свои).
local function hash(seed: number, n: number): number
	local x = math.sin(seed * 12.9898 + n * 78.233) * 43758.5453
	return x - math.floor(x)
end

-- Рыба над головой шлёпает хвостом вместе с рывком рук (FishingFxController.KickHeldFish).
local function kickFish(f: Fisher, power: number)
	if fx and type(fx.KickHeldFish) == "function" then
		pcall(fx.KickHeldFish, f.player, power)
	end
end

-- Добавочное движение фазы (k — вес слоя 0..1).
local LAYER: { [string]: (f: Fisher, now: number, add: Add, k: number) -> () } = {}

LAYER.Hold = function(f: Fisher, now: number, add: Add, k: number)
	addRot(add, "RShoulder", 1.5 * k * wave(now, 0.4, f.seed), 0, 0)
	addRot(add, "Waist", 0.8 * k * wave(now, 0.25, f.seed), 0, 0.8 * k * wave(now, 0.18, f.seed))
end
LAYER.Ready = LAYER.Hold

-- Ожидание: раз в FisherPoses.Timing.Fidget с одно «живое» движение (по кругу, с разной паузой):
-- 1 — переступил (таз вбок), 2 — дёрнул удочкой, 3 — огляделся, 4 — притопнул. Не во время
-- «примерки» (поплавок притоплен).
local FIDGET_TIME = { 1.2, 0.35, 1, 0.7 }
local function fidget(f: Fisher, now: number, add: Add, k: number, dip: number)
	if k > 0.5 and now >= f.nextFidget then
		if dip < 0.2 then
			f.fidgets += 1
			f.fidgetKind = 1 + (f.fidgets + math.floor(f.seed * 7)) % 4
			f.fidgetAt = now
		end
		local range = T.Fidget
		f.nextFidget = now + range.Min + (range.Max - range.Min) * hash(f.seed, f.fidgets)
	end
	local kind = f.fidgetKind
	if kind == 0 then
		return
	end
	local u = (now - f.fidgetAt) / FIDGET_TIME[kind]
	if u >= 1 then
		f.fidgetKind = 0
		return
	end
	local side = if f.fidgets % 2 == 0 then 1 else -1
	local e = k * math.sin(math.pi * u)
	if kind == 1 then
		local shift = k * (1 - math.cos(2 * math.pi * u)) / 2
		addMove(add, "Root", 0.15 * side * shift, 0, 0)
		addRot(add, "Root", 0, 0, -4 * side * shift)
		addRot(add, "Waist", 0, 0, 6 * side * shift)
	elseif kind == 2 then
		addRot(add, "RWrist", 12 * e, 0, 0)
		addRot(add, "RShoulder", 5 * e, 0, 0)
	elseif kind == 3 then
		local g = k * smoothstep(0, 0.25, u) * (1 - smoothstep(0.7, 1, u))
		addRot(add, "Neck", 4 * g, 30 * side * g, 0)
		addRot(add, "Waist", 0, 8 * side * g, 0)
	else
		local tap = k * math.max(0, math.sin(2 * math.pi * 2 * u))
		addRot(add, "RHip", 14 * tap, 0, 0)
		addRot(add, "RKnee", -24 * tap, 0, 0)
	end
end

LAYER.Wait = function(f: Fisher, now: number, add: Add, k: number)
	local dip = dipOf(f)
	addRot(add, "RShoulder", k * (2 * wave(now, 0.45, f.seed) - 14 * dip), 0, 0)
	addRot(add, "RWrist", -18 * dip * k, 0, 0)
	addRot(add, "Waist", k * wave(now, 0.25, f.seed), 0, 1.5 * k * wave(now, 0.3, f.seed))
	fidget(f, now, add, k, dip)
end

-- Клюёт: дрожит, кончик удочки и весь рыбак дёргаются вниз с каждым нырком поплавка.
LAYER.Bite = function(f: Fisher, now: number, add: Add, k: number)
	local dip = dipOf(f)
	addRot(add, "RShoulder", k * (1.5 * wave(now, 11, f.seed) - 16 * dip), 0, 0)
	addRot(add, "RWrist", k * (1.5 * wave(now, 11, f.seed + 1) - 18 * dip), 0, 0)
	addRot(add, "Waist", -5 * dip * k, 0, -4 * dip * k)
	addMove(add, "Root", 0, -0.12 * dip * k, 0)
end

LAYER.Cast = function(f: Fisher, now: number, add: Add, k: number)
	-- «взведён»: дрожь, пока ждём CastTime
	local windAt, releaseAt = f.windAt, f.releaseAt
	if windAt and now >= windAt and (releaseAt == nil or now < releaseAt - T.Swing) then
		addRot(add, "RShoulder", 2.5 * k * wave(now, 9, f.seed), 0, 0)
		addRot(add, "Waist", 0.8 * k * wave(now, 0.9, f.seed), 0, 0)
	end
end

LAYER.Reel = function(f: Fisher, now: number, add: Add, k: number)
	local s = intensity(f) * k
	local t = now + f.seed
	-- левая рука крутит катушку (плечо и локоть со сдвигом фаз 90°)
	addRot(add, "LShoulder", 14 * s * wave(now, CRANK_HZ), 0, 0)
	addRot(add, "LElbow", 26 * s * wave(now, CRANK_HZ, math.pi / 2), 0, 0)
	-- рыба мотает поплавок (FishingFxController: влево на sin(t·ReelSpeed)): удочку ведёт за ним,
	-- рыбака дёргает к рыбе (таз вбок), корпус откидывается против рывка
	local pull = math.sin(t * REEL_SPEED)
	addRot(add, "RShoulder", 0, 18 * s * pull, 0)
	addRot(add, "Waist", 0, 6 * s * pull, -8 * s * pull)
	addMove(add, "Root", -0.22 * s * pull, 0, 0)
	-- дрожь натяжения
	addRot(add, "RWrist", 1.5 * s * wave(now, 13, f.seed), 0, 0)
	addRot(add, "RElbow", 1.5 * s * wave(now, 13, f.seed + 2), 0, 0)
end
LAYER.Strike = function(f: Fisher, now: number, add: Add, k: number)
	LAYER.Reel(f, now, add, k * smoothstep(0.15, 0.45, now - f.modeSince))
end

LAYER.Retract = function(f: Fisher, now: number, add: Add, k: number)
	local u = now - f.modeSince
	local e = k * (1 - smoothstep(T.Retract.Crank - 0.1, T.Retract.Crank + 0.1, u))
	addRot(add, "LShoulder", 12 * e * wave(now, RETRACT_CRANK_HZ), 0, 0)
	addRot(add, "LElbow", 24 * e * wave(now, RETRACT_CRANK_HZ, math.pi / 2), 0, 0)
end

LAYER.Caught = function(f: Fisher, now: number, add: Add, k: number)
	-- взгляд вверх за прыжком рыбы, к приземлению — обратно (рыба приварена к голове)
	local u = now - f.caughtAt
	local leap = FishingConfig.LeapTime
	local up = smoothstep(0.3, T.Caught.LookUp, u) * (1 - smoothstep(leap - 0.15, leap + 0.1, u))
	addRot(add, "Neck", 25 * up * k, 0, 0)
end

-- Рыба над головой: дышит, колени пружинят; раз в Trophy.ShowEvery с «показ» — рывок руками
-- вместе со шлепком рыбы (FishLife.kick) и поворот корпуса с рыбой влево-вправо.
LAYER.Trophy = function(f: Fisher, now: number, add: Add, k: number)
	local breath = wave(now, 0.8, f.seed)
	addRot(add, "RShoulder", 5 * k * breath, 0, 0)
	addRot(add, "LShoulder", 5 * k * breath, 0, 0)
	addRot(add, "Neck", 2 * k * wave(now, 0.8, f.seed + 1.2), 0, 0)
	addMove(add, "Root", 0, -0.08 * k * (1 - math.cos(2 * math.pi * 1.2 * (now + f.seed))) / 2, 0)
	if k > 0.5 and now >= f.nextShow then
		f.nextShow = now + T.Trophy.ShowEvery
		pulse(f, "pump", 0.45, 1)
		pulse(f, "sweep", T.Trophy.ShowSweep, 1)
		kickFish(f, 0.8)
	end
end

-- Сорвалась: левая рука повисла и качнулась, голова качается «эх!».
LAYER.Lost = function(f: Fisher, now: number, add: Add, k: number)
	local u = now - f.modeSince
	local from, to = T.Lost.ShakeFrom, T.Lost.ShakeTo
	if u > from and u < to then
		local e = envelope((u - from) / (to - from), 0.15)
		addRot(add, "Neck", 0, 20 * e * k * math.sin(2 * math.pi * 2.5 * (u - from)), 0)
	end
	if u > 0.1 and u < 1.1 then
		local v = u - 0.1
		addRot(add, "LShoulder", 14 * k * math.exp(-4 * v) * math.sin(2 * math.pi * 1.6 * v), 0, 0)
	end
end

-- Импульсы (u — доля 0..1, amount — масштаб).
local PULSE: { [string]: (u: number, add: Add, amount: number, f: Fisher) -> () } = {
	-- поклёвка: вздрогнул — подскок, плечи вверх, удочка рывком вверх
	startle = function(u: number, add: Add, amount: number)
		local e = envelope(u, 0.2) * amount
		addRot(add, "Waist", 16 * e, 0, 0)
		addRot(add, "RShoulder", 22 * e, 0, 12 * e)
		addRot(add, "LShoulder", 0, 0, -12 * e)
		addMove(add, "Root", 0, 0.2 * e, 0)
	end,
	-- подсечка: рывок с подскоком
	yank = function(u: number, add: Add, amount: number)
		local e = math.sin(math.pi * u) * amount
		addMove(add, "Root", 0, 0.35 * e, 0)
		addRot(add, "Waist", 8 * e, 0, 0)
	end,
	-- эпическая и выше: подпрыгнул, когда рыба выскочила
	hop = function(u: number, add: Add, amount: number)
		local e = math.sin(math.pi * u) * amount
		addMove(add, "Root", 0, 0.45 * e, 0)
		addRot(add, "RShoulder", 10 * e, 0, 0)
	end,
	-- рыба приземлилась над головой: присел под её весом и подпрыгнул от радости (amount —
	-- доля полного прыжка), приземлился
	bounce = function(u: number, add: Add, amount: number)
		local up = 0.55 * amount
		local y = if u < 0.3
			then -0.25 * math.sin(u / 0.3 * math.pi / 2)
			elseif u < 0.65 then -0.25 + (0.25 + up) * math.sin((u - 0.3) / 0.35 * math.pi / 2)
			else up * math.cos((u - 0.65) / 0.35 * math.pi / 2)
		addMove(add, "Root", 0, y, 0)
	end,
	-- легендарная / мифическая: оборот на месте с рыбой над головой
	spin = function(u: number, add: Add, amount: number)
		addRot(add, "Root", 0, 360 * amount * u * u * (3 - 2 * u), 0)
	end,
	-- «качание» трофеем: руки вверх-вниз и чуть в стороны, рыбак пружинит (amount — сколько качаний)
	pump = function(u: number, add: Add, amount: number)
		local swing = math.sin(2 * math.pi * amount * u) * (1 - u)
		addRot(add, "RShoulder", 16 * swing, 0, 8 * swing)
		addRot(add, "LShoulder", 16 * swing, 0, -8 * swing)
		addMove(add, "Root", 0, -0.12 * math.abs(swing), 0)
	end,
	-- поворот корпуса с рыбой влево-вправо (показать трофей)
	sweep = function(u: number, add: Add, amount: number)
		addRot(add, "Waist", 0, 15 * amount * math.sin(2 * math.pi * u), 0)
	end,
	-- попал в мини-игре: рывок удочкой (amount 1.6 — победное нажатие)
	tap = function(u: number, add: Add, amount: number)
		local e = math.sin(math.pi * u) * amount
		addRot(add, "RShoulder", 22 * e, 0, 0)
		addRot(add, "Waist", 6 * e, 0, -4 * e)
		addMove(add, "Root", 0, 0.08 * e, 0)
	end,
	-- нажал мимо зоны: удочка клюнула вниз, корпус качнулся
	fumble = function(u: number, add: Add, amount: number)
		local e = math.sin(math.pi * u) * amount
		addRot(add, "RShoulder", -10 * e, 0, 0)
		addRot(add, "Waist", 0, 0, 6 * e)
		addRot(add, "Neck", 0, 0, -6 * e)
	end,
	-- сорвалась: топнул с досады (нога вверх, удар, тело вздрогнуло)
	stomp = function(u: number, add: Add, amount: number)
		local lift = if u < 0.5
			then math.sin(u / 0.5 * math.pi / 2)
			elseif u < 0.62 then math.cos((u - 0.5) / 0.12 * math.pi / 2)
			else 0
		addRot(add, "RHip", 35 * lift * amount, 0, 0)
		addRot(add, "RKnee", -60 * lift * amount, 0, 0)
		if u >= 0.62 then
			addMove(add, "Root", 0, -0.1 * amount * math.sin((u - 0.62) / 0.38 * math.pi), 0)
		end
	end,
	-- заброс не принят: пожал плечами
	shrug = function(u: number, add: Add, amount: number)
		local e = math.sin(math.pi * u) * amount
		addRot(add, "RShoulder", 0, 0, 14 * e)
		addRot(add, "LShoulder", 0, 0, -14 * e)
		addRot(add, "Neck", -6 * e, 0, 6 * e)
	end,
}

--------------------------------------------------------------------------------
-- Фазы
--------------------------------------------------------------------------------

local refresh: (f: Fisher) -> ()

local function phase(f: Fisher, name: string)
	FisherAnimController.PhaseChanged:Fire(f.player, name)
end

local function setMode(f: Fisher, mode: string, now: number)
	if f.mode ~= mode then
		if f.active then
			for _, layer in f.layers do
				layer.target = 0 -- гаснут плавно (stepFisher их и уберёт)
			end
		else
			table.clear(f.layers) -- далеко, не анимируем: гасить некому — список не растёт
		end
		if LAYER[mode] then
			table.insert(f.layers, { mode = mode, w = 0, target = 1 })
		end
		f.mode = mode
		if mode == "Wait" then
			f.nextFidget = now + T.Fidget.Min
			f.fidgetKind = 0
		elseif mode == "Trophy" and f.nextShow < now then
			f.nextShow = now + 1 -- трофей без приземления (подошёл позже, снова держит после "Idle")
		end
		phase(f, mode)
	end
	f.modeSince = now
	f.modeEnd = nil
	f.nextMode = nil
end

-- Новая дорожка: от «снимка» текущей позы через ключи.
local function play(f: Fisher, mode: string, now: number, keys: { Key })
	table.insert(keys, 1, key(now, clone(f.last)))
	f.keys = keys
	setMode(f, mode, now)
	refresh(f)
end

local function trophyPose(f: Fisher): PoseData
	local rig = f.rig
	if rig and rig.rigType == "R6" then
		return POSES.TrophyR6
	end
	return if f.tool then POSES.TrophySling else POSES.TrophyNoRod
end

-- Ничего не происходит: рыба над головой — держим её, иначе удочка в руке (ещё Linger с).
local function rest(f: Fisher, now: number, blend: number)
	if f.heldFish then
		play(f, "Trophy", now, { key(now + blend, trophyPose(f), inOutSine) })
	elseif f.tool then
		f.lingerUntil = now + T.Linger
		play(f, "Hold", now, { key(now + blend, POSES.Hold, inOutSine) })
	else
		f.lingerUntil = now + blend
		play(f, "Hold", now, { key(now + blend, EMPTY, inOutSine) })
	end
end

local function restPose(f: Fisher): PoseData
	if f.heldFish then
		return trophyPose(f)
	end
	return if f.tool then POSES.Hold else EMPTY
end

-- После дорожки — сама следующая фаза (дорожка уже кончается её позой).
local function after(f: Fisher, at: number, mode: string)
	f.modeEnd = at
	f.nextMode = mode
end

local function startReady(f: Fisher, now: number)
	local r = T.Ready
	play(f, "Ready", now, {
		key(now + r.Up, POSES.Ready, outBack),
		key(now + r.Up + r.Hold, POSES.Ready),
		key(now + r.Up + r.Hold + r.Down, POSES.Hold, inOutSine),
	})
	f.lingerUntil = now + r.Up + r.Hold + r.Down + T.Linger
	after(f, now + r.Up + r.Hold + r.Down, "Hold")
end

-- os.clock() броска по CastTime (серверное время): не раньше, чем через LaunchGuard после того,
-- как мы его увидели (как FishingFxController: поплавок срывается в тот же миг).
local function releaseFromCastTime(f: Fisher, now: number): number?
	local castTime = f.player:GetAttribute("CastTime")
	if typeof(castTime) ~= "number" or castTime ~= castTime then
		return nil
	end
	local serverNow = Workspace:GetServerTimeNow()
	local start = math.max(castTime, serverNow + (FishingConfig.Fx.LaunchGuard or 0))
	local landing = castTime + FishingConfig.CastFlightTime
	if serverNow >= landing - 0.05 then
		return nil -- поплавок уже на воде (вошли в игру позже) — без заброса
	end
	return now + math.min(start, landing) - serverNow
end

-- Дорожка заброса: замах → (взведён) → бросок к releaseAt → проводка → Wait.
local function castTrack(f: Fisher, now: number)
	local releaseAt = f.releaseAt
	local windAt = f.windAt
	if windAt == nil or windAt <= now then
		windAt = if windAt and windAt <= now then now else now + T.WindUp
	end
	if releaseAt then
		-- сервер дал CastTime: замах успевает к releaseAt − Swing (или сжимается)
		windAt = math.min(windAt :: number, math.max(now + T.MinSwing, releaseAt - T.Swing))
	end
	f.windAt = windAt
	local keys = { key(windAt :: number, POSES.WindUp, outQuad) }
	if releaseAt then
		local swingFrom = math.max(windAt :: number, releaseAt - T.Swing)
		if swingFrom > (windAt :: number) + 1e-3 then
			table.insert(keys, key(swingFrom, POSES.WindUp))
		end
		local release = math.max(releaseAt, swingFrom + T.MinSwing)
		f.releaseAt = release
		table.insert(keys, key(release, POSES.Release, inCubic))
		table.insert(keys, key(release + T.Follow, POSES.Throw, outQuad))
		-- проводка держится за летящим поплавком до приводнения (CastTime + CastFlightTime)
		local castTime = f.player:GetAttribute("CastTime")
		local landing = release + FishingConfig.CastFlightTime
		if typeof(castTime) == "number" and castTime == castTime then
			local serverLanding = now + castTime + FishingConfig.CastFlightTime - Workspace:GetServerTimeNow()
			landing = math.clamp(serverLanding, release + T.Follow, landing)
		end
		if landing > release + T.Follow + 1e-3 then
			table.insert(keys, key(landing, POSES.Throw))
		end
		table.insert(keys, key(landing + T.Settle, POSES.Wait, inOutSine))
		play(f, "Cast", now, keys)
		after(f, landing + T.Settle, "Wait")
	else
		play(f, "Cast", now, keys)
	end
end

local function startCast(f: Fisher, now: number, releaseAt: number?)
	f.castAt = now
	f.windAt = nil
	f.releaseAt = releaseAt
	f.released = false
	castTrack(f, now)
end

local function startWait(f: Fisher, now: number)
	play(f, "Wait", now, { key(now + T.Wait, POSES.Wait, inOutSine) })
end

local function startBite(f: Fisher, now: number)
	play(f, "Bite", now, { key(now + T.Bite.Startle + T.Bite.Settle, POSES.Bite, outQuad) })
	pulse(f, "startle", T.Bite.Startle + 0.15)
end

local function startStrike(f: Fisher, now: number)
	local s = T.Strike
	play(f, "Strike", now, {
		key(now + s.Up, POSES.Strike, outQuad),
		key(now + s.Up + s.Hold, POSES.Strike),
		key(now + s.Up + s.Hold + s.Down, POSES.Reel, outBack),
	})
	after(f, now + s.Up + s.Hold + s.Down, "Reel")
	f.loadPulseUntil = now + s.Up + s.Hold
	pulse(f, "yank", s.Up + s.Hold + 0.15)
end

local function startReel(f: Fisher, now: number)
	play(f, "Reel", now, { key(now + T.Reel, POSES.Reel, inOutSine) })
end

local function startRetract(f: Fisher, now: number)
	local r = T.Retract
	play(f, "Retract", now, {
		key(now + r.Up, POSES.Retract, outQuad),
		key(now + r.Crank, POSES.Retract),
		key(now + r.Crank + r.Down, restPose(f), inOutSine),
	})
	after(f, now + r.Crank + r.Down, "Rest")
end

local function startCaught(f: Fisher, now: number, rarity: string)
	local c = T.Caught
	local leap = FishingConfig.LeapTime
	f.caughtAt = now
	f.landed = false
	f.rarity = rarity
	play(f, "Caught", now, {
		key(now + c.Yank, POSES.Yank, outBack),
		key(now + math.max(c.Yank, leap - c.Raise), POSES.Yank),
		key(now + math.max(c.Yank, leap - c.Raise) + c.Raise, trophyPose(f), outBack),
	})
	if BIG_CATCH[rarity] then
		pulse(f, "hop", 0.35, 1, 0.05)
	end
end

-- Рыба приземлилась над головой: присел под её весом и подпрыгнул (обычная — пониже), качает
-- её руками; легендарная / мифическая — ещё оборот на месте с рыбой. Дальше — «показы» рыбы
-- (LAYER.Trophy) через Trophy.FirstShow.
local function land(f: Fisher, now: number)
	if f.landed then
		return
	end
	f.landed = true
	local rarity = f.rarity or "Common"
	pulse(f, "bounce", T.Caught.Bounce, if rarity == "Common" then 0.65 else 1)
	local pumps = if RARE_CATCH[rarity] then 3 else 2
	pulse(f, "pump", pumps / 2.5, pumps)
	if RARE_CATCH[rarity] then
		pulse(f, "spin", T.Caught.Spin, 1, 0.12)
	end
	f.nextShow = now + T.Trophy.FirstShow
	phase(f, "Landed")
	if f.heldFish then
		setMode(f, "Trophy", now) -- дорожка уже кончается позой трофея
	end
end

local function startLost(f: Fisher, now: number)
	local l = T.Lost
	play(f, "Lost", now, {
		key(now + l.Slump, POSES.Slump, outQuad),
		key(now + l.Hold, POSES.Slump),
		key(now + l.Hold + l.Recover, restPose(f), inOutSine),
	})
	after(f, now + l.Hold + l.Recover, "Rest")
	pulse(f, "stomp", 0.45, 1, 0.1)
end

-- Повтор своего трофея после карточки (FishingFxController.TrophyReplayed) — настоящий
-- праздник (≈ Celebrate с): присел и подпрыгнул, ещё прыжок, три качания и поворот с рыбой.
local function celebrate(f: Fisher, now: number)
	local d = T.Celebrate
	pulse(f, "bounce", T.Caught.Bounce, 1)
	pulse(f, "hop", 0.35, 1, T.Caught.Bounce + 0.05)
	pulse(f, "pump", d, 3)
	pulse(f, "sweep", d, 1)
	f.nextShow = now + d + T.Trophy.ShowEvery
end

local function cancelCast(f: Fisher, now: number)
	if f.mode == "Cast" and f.releaseAt == nil then
		pulse(f, "shrug", T.Cancel)
		rest(f, now, T.Cancel)
	end
end

--------------------------------------------------------------------------------
-- События рыбака
--------------------------------------------------------------------------------

local function parseFx(value: any): (string?, string?)
	if typeof(value) ~= "string" then
		return nil, nil
	end
	local fields = string.split(value, "|")
	local kind = fields[2]
	if kind ~= "caught" and kind ~= "lost" then
		return nil, nil
	end
	local rarity = fields[5]
	return kind, if rarity and rarity ~= "" then rarity else "Common"
end

local function onFxChanged(f: Fisher)
	local value = f.player:GetAttribute("FishFx")
	if value == f.fxValue then
		return
	end
	f.fxValue = value
	local kind, rarity = parseFx(value)
	if not kind then
		return
	end
	local now = os.clock()
	f.fxAt = now
	if kind == "caught" then
		startCaught(f, now, rarity or "Common")
	else
		startLost(f, now)
	end
end

local function onStateChanged(f: Fisher)
	local state = f.player:GetAttribute("FishingState")
	state = if typeof(state) == "string" then state else "Idle"
	if state == f.state then
		return
	end
	local previous = f.state
	f.state = state
	local now = os.clock()
	if state == "Waiting" then
		local releaseAt = releaseFromCastTime(f, now)
		if f.mode == "Cast" and f.releaseAt == nil and releaseAt then
			-- свой заброс «вслепую»: теперь известен миг броска
			f.releaseAt = releaseAt
			castTrack(f, now)
		elseif releaseAt then
			startCast(f, now, releaseAt)
		else
			startWait(f, now)
		end
	elseif state == "Bite" then
		startBite(f, now)
	elseif state == "Reeling" then
		if f.mode ~= "Strike" and f.mode ~= "Reel" then
			if previous == "Bite" then
				startStrike(f, now)
			else
				startReel(f, now)
			end
		end
	elseif state == "Idle" then
		-- улов / потеря только что начались — это их конец рыбалки, не «сматываем»
		local recent = now - f.fxAt < EVENT_GRACE
		if f.mode == "Caught" or f.mode == "Lost" or recent then
			return
		end
		if f.mode == "Cast" and f.releaseAt == nil then
			return -- свой заброс «вслепую» ещё ждёт ответа (CastTimeout)
		end
		if FISHING[f.mode] then
			startRetract(f, now)
		end
	end
end

local function onHeldAdded(f: Fisher, held: Instance)
	f.heldFish = held
	local now = os.clock()
	if f.mode == "Caught" then
		if now - f.caughtAt >= FishingConfig.LeapTime - 0.2 then
			land(f, now)
		end
	elseif not FISHING[f.mode] then
		play(f, "Trophy", now, { key(now + 0.3, trophyPose(f), outBack) })
	end
	refresh(f)
end

local function onHeldRemoved(f: Fisher, held: Instance)
	if f.heldFish ~= held then
		return
	end
	f.heldFish = nil
	local now = os.clock()
	if f.mode == "Trophy" or (f.mode == "Caught" and f.landed) then
		rest(f, now, T.TrophyDown)
	end
end

local function isRod(child: Instance): boolean
	return child:IsA("Tool") and typeof(child:GetAttribute("RodId")) == "string"
end

local function onToolAdded(f: Fisher, tool: Tool)
	if f.rod then
		FisherRod.restore(f.rod)
	end
	f.tool = tool
	f.rod = nil
	local now = os.clock()
	if not FISHING[f.mode] and f.mode ~= "Trophy" then
		startReady(f, now)
	end
end

local function onToolRemoved(f: Fisher, tool: Tool)
	if f.tool ~= tool then
		return
	end
	if f.rod then
		FisherRod.restore(f.rod)
	end
	f.tool = nil
	f.rod = nil
	if f.mode == "Ready" or f.mode == "Hold" then
		f.lingerUntil = 0
	end
end

--------------------------------------------------------------------------------
-- Активация: кого анимируем
--------------------------------------------------------------------------------

local function viewerPosition(): Vector3?
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local camera = Workspace.CurrentCamera
	return if camera then camera.CFrame.Position else nil
end

local function inRange(f: Fisher): boolean
	local root = f.root
	if not root or root.Parent == nil then
		return false
	end
	local viewer = viewerPosition()
	return viewer == nil or (viewer - root.Position).Magnitude <= RANGE
end

local function engaged(f: Fisher): boolean
	local me = Players.LocalPlayer
	return f.mode ~= "None"
		and f.character ~= nil
		and FisherAnimController.Enabled
		and not (me and me:GetAttribute("FisherAnimOff"))
end

local function ensureRig(f: Fisher, now: number): boolean
	local rig = f.rig
	if rig and FisherRig.isAlive(rig) then
		return true
	end
	if rig then
		FisherRig.releaseAll(rig)
	end
	f.rig = nil
	local character = f.character
	if not character then
		return false
	end
	f.rig = FisherRig.build(character)
	f.nextAlive = now + ALIVE_CHECK
	return f.rig ~= nil
end

local frame: (dt: number) -> ()
local startPolling: () -> ()

local function ensureConnection()
	if connection == nil and next(active) ~= nil then
		connection = RunService.PreSimulation:Connect(frame)
	end
end

local function deactivate(f: Fisher)
	if f.rig then
		FisherRig.releaseAll(f.rig)
	end
	if f.rod then
		FisherRod.restore(f.rod)
	end
	f.active = false
	f.master = 0
	table.clear(f.last.cf)
	table.clear(f.last.w)
	-- импульсы и погасшие слои больше некому доигрывать: остаётся слой текущей фазы
	table.clear(f.pulses)
	table.clear(f.layers)
	if LAYER[f.mode] then
		table.insert(f.layers, { mode = f.mode, w = 0, target = 1 })
	end
	active[f] = nil
	if engaged(f) then
		startPolling() -- ушёл далеко, а рыбалка идёт: вернётся — подхватим
	end
end

-- Смены фаз по времени (конец дорожки, конец «задержки», свой заброс без ответа, рыба над
-- головой так и не появилась). Идут и у неанимируемых (далёких) рыбаков — из таймера опроса.
local function advance(f: Fisher, now: number)
	local modeEnd = f.modeEnd
	if modeEnd and now >= modeEnd then
		local nextMode = f.nextMode
		f.modeEnd, f.nextMode = nil, nil
		if nextMode == "Rest" then
			rest(f, now, 0.2)
		elseif nextMode then
			setMode(f, nextMode, now)
		end
	end
	if f.mode == "Cast" and f.releaseAt == nil and f.castAt and now - f.castAt > T.CastTimeout then
		cancelCast(f, now)
	end
	if f.mode == "Caught" and not f.landed then
		local leap = FishingConfig.LeapTime
		if f.heldFish and now - f.caughtAt >= leap - 0.05 then
			land(f, now)
		elseif now - f.caughtAt >= leap + (FishingConfig.Fx.HandoffWait or 0.6) + 0.5 then
			land(f, now)
			rest(f, now, T.TrophyDown) -- рыбы над головой так и нет
		end
	end
	if f.mode == "Hold" and now >= f.lingerUntil then
		f.mode = "None"
		f.modeSince = now
		phase(f, "None")
		f.masterTarget = 0
	end
	if f.mode == "Cast" and not f.released and f.releaseAt and now >= (f.releaseAt :: number) then
		f.released = true
		phase(f, "Release")
	end
end

refresh = function(f: Fisher)
	local now = os.clock()
	local wanted = engaged(f) and inRange(f)
	if wanted and not f.active then
		if not ensureRig(f, now) then
			startPolling()
			return
		end
		f.active = true
		f.master = 0
		table.clear(f.last.cf)
		table.clear(f.last.w)
		f.lastPosition = nil
		active[f] = true
		ensureConnection()
	end
	if f.active then
		f.masterTarget = if wanted then 1 else 0
	elseif engaged(f) then
		startPolling() -- далеко или ещё не загрузился: проверим позже
	end
end

startPolling = function()
	if polling then
		return
	end
	polling = true
	task.delay(POLL, function()
		polling = false
		local again = false
		local now = os.clock()
		for _, f in fishers do
			if engaged(f) and not f.active then
				advance(f, now)
				refresh(f)
				again = again or (engaged(f) and not f.active)
			end
		end
		if again then
			startPolling()
		end
	end)
end

--------------------------------------------------------------------------------
-- Кадр (PreSimulation)
--------------------------------------------------------------------------------

local function approach(value: number, target: number, dt: number, time: number): number
	return value + (target - value) * (1 - math.exp(-dt / time))
end

local function flatYaw(cframe: CFrame, target: Vector3): number
	local v = cframe:VectorToObjectSpace(target - cframe.Position)
	if v.X * v.X + v.Z * v.Z < 0.01 then
		return 0
	end
	return math.atan2(-v.X, -v.Z) / DEG
end

local function bobberPoint(f: Fisher): Vector3?
	if fx and type(fx.GetBobber) == "function" then
		local ok, bobber = pcall(fx.GetBobber, f.player)
		if ok and typeof(bobber) == "Instance" and bobber:IsA("Model") then
			local model = bobber :: Model
			return model:GetPivot().Position
		end
	end
	return f.water
end

-- Торс и голова персонажа (кэш; заменили — ищем снова).
local function bodyParts(f: Fisher, rig: FisherRig.Rig): (BasePart?, BasePart?)
	local character = f.character
	local torso, head = f.torsoPart, f.headPart
	if character and (not torso or torso.Parent ~= character or not head or head.Parent ~= character) then
		local t = character:FindFirstChild(if rig.rigType == "R15" then "UpperTorso" else "Torso")
		local h = character:FindFirstChild("Head")
		torso = if t and t:IsA("BasePart") then t else nil
		head = if h and h:IsA("BasePart") then h else nil
		f.torsoPart, f.headPart = torso, head
	end
	return torso, head
end

-- Скорость персонажа по сдвигу HumanoidRootPart (MoveDirection чужих не реплицируется).
local function trackMotion(f: Fisher, root: BasePart, dt: number)
	local position = root.Position
	local last = f.lastPosition
	f.lastPosition = position
	if not last or dt <= 0 then
		return
	end
	local delta = position - last
	if delta.Magnitude > 20 then
		return -- телепорт
	end
	local flat = Vector3.new(delta.X, 0, delta.Z).Magnitude / dt
	f.speed = approach(f.speed, flat, dt, SPEED_TIME)
	f.vy = approach(f.vy, delta.Y / dt, dt, SPEED_TIME)
end

local function rodLoad(f: Fisher, now: number): number
	local mode = f.mode
	local load = 0
	if mode == "Wait" then
		load = 3 + 10 * dipOf(f)
	elseif mode == "Bite" then
		load = 6 + 20 * dipOf(f)
	elseif mode == "Strike" then
		load = if now < f.loadPulseUntil then 34 else 28
	elseif mode == "Reel" then
		load = (28 + 12 * math.abs(math.sin((now + f.seed) * REEL_SPEED))) * math.sqrt(intensity(f))
		if now < f.loadPulseUntil then
			load -= 10
		end
	elseif mode == "Retract" then
		load = 4
	end
	return load * DEG
end

local scratch: PoseData = { cf = {}, w = {} }
local scratchAdd: Add = {}

local function stepFisher(f: Fisher, now: number, dt: number)
	local rig = f.rig
	local root = f.root
	local humanoid = f.humanoid
	if not rig or not root or not humanoid then
		f.masterTarget = 0
		f.master = 0
		return
	end
	if now >= f.nextAlive then
		f.nextAlive = now + ALIVE_CHECK
		if not FisherRig.isAlive(rig) then
			if not ensureRig(f, now) then
				f.masterTarget = 0
				f.master = 0
				return
			end
			rig = f.rig :: FisherRig.Rig
		end
	end

	advance(f, now)
	if not inRange(f) or not engaged(f) then
		f.masterTarget = 0
	end

	-- общий вес слоя и веса групп (идёт / в воздухе / умер / сидит)
	local masterTime = if f.masterTarget > f.master then T.FadeIn else T.FadeOut
	f.master = approach(f.master, f.masterTarget, dt, masterTime / 3)
	if f.masterTarget == 0 and f.master < 0.01 then
		deactivate(f)
		return
	end
	trackMotion(f, root, dt)
	local moving = f.speed > MOVE_SPEED or math.abs(f.vy) > AIR_SPEED
	local alive = humanoid.Health > 0 and not humanoid.Sit
	local armsTarget = 1
	if moving then
		armsTarget = if f.mode == "Trophy" or f.mode == "Caught" then 1 elseif FISHING[f.mode] then 0.7 else 0
	end
	f.arms = approach(f.arms, if alive then armsTarget else 0, dt, GROUP_TIME / 3)
	f.torso = approach(f.torso, if alive and not moving then 1 else 0, dt, GROUP_TIME / 3)
	f.head = approach(f.head, if alive and not moving then 1 else 0, dt, GROUP_TIME / 3)

	-- поза дорожки (f.last — «снимок» для следующего перехода) и рабочая копия
	evaluate(f.keys, now, f.last)
	local cf, w = scratch.cf, scratch.w
	table.clear(cf)
	table.clear(w)
	for channel, value in f.last.cf do
		cf[channel] = value
		w[channel] = f.last.w[channel]
	end

	-- добавки: слои фаз (плавно), импульсы
	local add = scratchAdd
	table.clear(add)
	local layers = f.layers
	for i = #layers, 1, -1 do
		local layer = layers[i]
		layer.w = approach(layer.w, layer.target, dt, LAYER_TIME / 3)
		if layer.target == 0 and layer.w < 0.01 then
			table.remove(layers, i)
		else
			local fn = LAYER[layer.mode]
			if fn then
				fn(f, now, add, layer.w)
			end
		end
	end
	local pulses = f.pulses
	for i = #pulses, 1, -1 do
		local p = pulses[i]
		local u = (now - p.at) / p.duration
		if u >= 1 then
			table.remove(pulses, i)
		elseif u >= 0 then
			PULSE[p.kind](u, add, p.amount, f)
		end
	end

	-- к поплавку: корпус (пополам таз и талия) — к точке на воде (BobberTarget: летящий над
	-- головой поплавок с рыбой не крутит корпус), взгляд — на сам поплавок (он же — куда тянет
	-- леска удочку: один раз за кадр)
	local water = f.water
	local facing = if FISHING[f.mode] then water else nil
	local target = if LOOK[f.mode] then bobberPoint(f) else nil
	local rootCFrame = root.CFrame
	local yawTarget = if facing then math.clamp(flatYaw(rootCFrame, facing), -YAW_LIMIT, YAW_LIMIT) else 0
	f.yaw = approach(f.yaw, yawTarget, dt, YAW_TIME / 3)
	if math.abs(f.yaw) > 0.05 then
		addRot(add, "Root", 0, f.yaw * 0.5, 0)
		addRot(add, "Waist", 0, f.yaw * 0.5, 0)
	end
	f.lookW = approach(f.lookW, if target then LOOK[f.mode] or 0 else 0, dt, 0.25 / 3)
	if target then
		f.lookTarget = target
	end
	local lookTarget = f.lookTarget -- (взгляд гаснет плавно — к последней точке)
	if f.lookW > 0.01 and lookTarget then
		local torso, head = bodyParts(f, rig)
		if torso and head then
			local v = torso.CFrame:VectorToObjectSpace(lookTarget - head.Position)
			local flat = math.sqrt(v.X * v.X + v.Z * v.Z)
			local yaw = math.clamp(math.atan2(-v.X, -v.Z) / DEG, -LOOK_YAW, LOOK_YAW)
			local pitch = math.clamp(math.atan2(v.Y, flat) / DEG, -LOOK_DOWN, LOOK_UP)
			f.lookYaw = approach(f.lookYaw, yaw, dt, LOOK_TIME / 3)
			f.lookPitch = approach(f.lookPitch, pitch, dt, LOOK_TIME / 3)
			local look = rot(f.lookPitch, f.lookYaw, 0)
			local neck = cf.Neck
			cf.Neck = if neck then neck:Lerp(look, f.lookW) else look
			w.Neck = math.max(w.Neck or 0, f.lookW)
		end
	end

	-- таз: сдвиг в масштабе роста; R15 — колени держат ступни на земле
	local scale = rig.scale
	local rootPose = cf.Root
	if rootPose then
		cf.Root = CFrame.new(rootPose.Position * scale) * rootPose.Rotation
	end
	local rootAdd = add.Root
	if rootAdd then
		add.Root = CFrame.new(rootAdd.Position * scale) * rootAdd.Rotation
	end
	if rig.rigType == "R15" then
		local drop = -((if cf.Root then cf.Root.Y * (w.Root or 0) else 0) + (if add.Root then add.Root.Y else 0))
		local theta = FisherRig.legBend(rig, drop) / DEG
		if theta > 0.01 then
			addRot(add, "RHip", theta, 0, 0)
			addRot(add, "LHip", theta, 0, 0)
			addRot(add, "RKnee", -2 * theta, 0, 0)
			addRot(add, "LKnee", -2 * theta, 0, 0)
			addRot(add, "RAnkle", theta, 0, 0)
			addRot(add, "LAnkle", theta, 0, 0)
		end
	end
	FisherRig.fold(rig, cf, w, add)

	-- запись
	local arms, torso, headW = f.arms * f.master, f.torso * f.master, f.head * f.master
	for channel, joint in rig.joints do
		local group = GROUP[channel]
		local g = if group == "torso" then torso elseif group == "head" then headW else arms
		local weight = (w[channel] or 0) * g
		local extra = add[channel]
		if extra and g < 0.999 then
			extra = if g > 0.001 then IDENTITY:Lerp(extra, g) else nil
		end
		local pose = cf[channel]
		if (pose and weight > 0.001) or extra then
			FisherRig.write(joint, pose, weight, extra)
		else
			FisherRig.release(joint)
		end
	end

	-- удочка
	local tool = f.tool
	if tool and not f.rod and tool.Parent == f.character then
		f.rod = FisherRod.attach(tool)
	end
	local rod = f.rod
	if rod then
		local viewer = viewerPosition()
		if viewer and (viewer - root.Position).Magnitude > ROD_NEAR then
			FisherRod.restore(rod) -- далеко: прямая, без записей (изгиб — пара пикселей)
		else
			local load = rodLoad(f, now) * f.master
			-- в борьбе удочку ещё и хлещет вбок вслед за рывками рыбы (поплавок — влево на sin)
			local side = if f.mode == "Reel"
				then root.CFrame.RightVector * (-0.4 * load * math.sin((now + f.seed) * REEL_SPEED))
				else nil
			FisherRod.step(rod, dt, load, target, side, if intensity(f) >= EPIC_INTENSITY then EPIC_BEND else nil)
		end
	end
end

frame = function(dt: number)
	local now = os.clock()
	for f in active do
		local ok, err = pcall(stepFisher, f, now, dt)
		if not ok then
			warn("[FisherAnimController] анимация рыбака упала:", err)
			f.mode = "None"
			deactivate(f)
		end
	end
	if next(active) == nil and connection then
		connection:Disconnect()
		connection = nil
	end
end

--------------------------------------------------------------------------------
-- Игроки и персонажи
--------------------------------------------------------------------------------

local function bindCharacter(f: Fisher, character: Model?)
	f.charTrove:Clean()
	if f.rig then
		FisherRig.releaseAll(f.rig)
	end
	if f.rod then
		FisherRod.restore(f.rod)
	end
	if f.active then
		deactivate(f)
	end
	f.character = character
	f.rig = nil
	f.rod = nil
	f.tool = nil
	f.heldFish = nil
	f.root = nil
	f.humanoid = nil
	f.torsoPart = nil
	f.headPart = nil
	f.mode = "None"
	f.keys = {}
	f.layers = {}
	f.pulses = {}
	if not character then
		return
	end
	local function setRoot()
		local root = character:FindFirstChild("HumanoidRootPart")
		f.root = if root and root:IsA("BasePart") then root else nil
		f.humanoid = character:FindFirstChildOfClass("Humanoid")
	end
	setRoot()
	local function added(child: Instance)
		if child.Name == "HumanoidRootPart" or child:IsA("Humanoid") then
			setRoot()
		elseif isRod(child) then
			onToolAdded(f, child :: Tool)
		elseif child.Name == "HeldFish" and child:IsA("Model") then
			onHeldAdded(f, child)
		end
	end
	f.charTrove:Connect(character.ChildAdded, added)
	f.charTrove:Connect(character.ChildRemoved, function(child: Instance)
		if child:IsA("Tool") then
			onToolRemoved(f, child)
		elseif child.Name == "HeldFish" then
			onHeldRemoved(f, child)
		end
	end)
	for _, child in character:GetChildren() do
		if isRod(child) then
			-- удочка уже в руке (вошли в игру позже) — без «взял удочку»
			f.tool = child :: Tool
		elseif child.Name == "HeldFish" and child:IsA("Model") then
			f.heldFish = child
		end
	end
	-- рыбалка уже идёт — сразу в её позу (без заброса)
	local now = os.clock()
	local state = f.player:GetAttribute("FishingState")
	f.state = "Idle"
	if state == "Waiting" or state == "Bite" or state == "Reeling" then
		f.state = state :: string
		if state == "Reeling" then
			startReel(f, now)
		elseif state == "Bite" then
			startBite(f, now)
		else
			startWait(f, now)
		end
	elseif f.heldFish then
		play(f, "Trophy", now, { key(now + 0.3, trophyPose(f), outBack) })
	end
	refresh(f)
end

local function track(player: Player)
	if fishers[player] then
		return
	end
	local f: Fisher = {
		player = player,
		own = player == Players.LocalPlayer,
		seed = (player.UserId % 97) * 0.37, -- та же фаза, что у метаний поплавка (FishingFxController)
		trove = Trove.new(),
		charTrove = Trove.new(),
		character = nil,
		humanoid = nil,
		root = nil,
		rig = nil,
		nextAlive = 0,
		tool = nil,
		rod = nil,
		heldFish = nil,
		state = "Idle",
		fxValue = player:GetAttribute("FishFx"), -- событие до нас не повторяем
		fxAt = -math.huge,
		mode = "None",
		modeSince = 0,
		modeEnd = nil,
		nextMode = nil,
		keys = {},
		last = clone(EMPTY),
		layers = {},
		pulses = {},
		castAt = nil,
		windAt = nil,
		releaseAt = nil,
		released = false,
		caughtAt = -math.huge,
		landed = true,
		rarity = nil,
		lingerUntil = 0,
		active = false,
		master = 0,
		masterTarget = 0,
		arms = 1,
		torso = 1,
		head = 1,
		lastPosition = nil,
		speed = 0,
		vy = 0,
		yaw = 0,
		lookPitch = 0,
		lookYaw = 0,
		lookW = 0,
		lookTarget = nil,
		loadPulseUntil = 0,
		water = nil,
		torsoPart = nil,
		headPart = nil,
		tapAt = -math.huge,
		nextFidget = 0,
		fidgetAt = 0,
		fidgetKind = 0,
		fidgets = 0,
		nextShow = 0,
	}
	local function readWater()
		local water = player:GetAttribute("BobberTarget")
		f.water = if typeof(water) == "Vector3" then water else nil
	end
	readWater()
	fishers[player] = f
	f.trove:Add(function()
		bindCharacter(f, nil)
		f.charTrove:Clean()
	end)
	f.trove:Connect(player.AttributeChanged, function(name: string)
		if name == "FishingState" then
			onStateChanged(f)
		elseif name == "BobberTarget" then
			readWater()
		elseif name == "FishFx" then
			onFxChanged(f)
		elseif name == "CastTime" and f.mode == "Cast" and f.state == "Waiting" then
			-- новый заброс без "Idle" между ними (или CastTime пришёл позже состояния)
			local now = os.clock()
			local releaseAt = releaseFromCastTime(f, now)
			if releaseAt and (f.releaseAt == nil or math.abs(releaseAt - (f.releaseAt :: number)) > 0.05) then
				f.releaseAt = releaseAt
				castTrack(f, now)
			end
		end
	end)
	f.trove:Connect(player.CharacterAdded, function(character: Model)
		bindCharacter(f, character)
	end)
	f.trove:Connect(player.CharacterRemoving, function()
		bindCharacter(f, nil)
	end)
	if player.Character then
		bindCharacter(f, player.Character)
	end
end

local function untrack(player: Player)
	local f = fishers[player]
	if f then
		fishers[player] = nil
		f.trove:Clean()
		active[f] = nil
		if next(active) == nil and connection then
			connection:Disconnect()
			connection = nil
		end
	end
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function FisherAnimController.Cue(name: string)
	local f = fishers[Players.LocalPlayer]
	if not f or not f.character then
		return
	end
	local now = os.clock()
	if name == "castPress" then
		if f.tool and (not FISHING[f.mode] or f.mode == "Lost" or f.mode == "Retract") then
			startCast(f, now, nil)
		end
	elseif name == "hookPress" then
		if f.state == "Bite" and f.mode == "Bite" then
			startStrike(f, now)
		end
	elseif name == "castCancel" then
		cancelCast(f, now)
	elseif name == "tapHit" or name == "tapWin" then
		-- попал (FishingController — сразу по нажатию, ещё до "Zone"): рывок удочкой; победное —
		-- сильнее, дальше рывок «Поймал» (Yank)
		if f.mode == "Reel" or f.mode == "Strike" then
			pulse(f, "tap", 0.22, if name == "tapWin" then 1.6 else 1)
			f.loadPulseUntil = now + 0.25
			f.tapAt = now
		end
	elseif name == "tapMiss" then
		-- мимо зоны: удочка клюнула вниз (рыба сорвётся — решит сервер, "Lost")
		if f.mode == "Reel" then
			pulse(f, "fumble", 0.25)
		end
	end
end

function FisherAnimController.GetPhase(player: Player): (string, number)
	local f = fishers[player]
	if not f then
		return "None", 0
	end
	return f.mode, f.modeSince
end

function FisherAnimController.IsAnimating(player: Player): boolean
	local f = fishers[player]
	return f ~= nil and f.active
end

function FisherAnimController.GetRodBend(player: Player): number
	local f = fishers[player]
	local rod = f and f.rod
	return if rod then FisherRod.bend(rod) else 0
end

-- Для тестов: длины списков слоёв и импульсов рыбака (у дальних не растут) и сколько было
-- «живых» движений в ожидании.
function FisherAnimController.GetDebug(player: Player): { layers: number, pulses: number, fidgets: number }?
	local f = fishers[player]
	if not f then
		return nil
	end
	return { layers = #f.layers, pulses = #f.pulses, fidgets = f.fidgets }
end

function FisherAnimController.GetRodTip(player: Player): Attachment?
	local f = fishers[player]
	local tool = f and f.tool
	local handle = tool and tool:FindFirstChild("Handle")
	local tip = handle and handle:FindFirstChild("TipAttachment")
	return if tip and tip:IsA("Attachment") then tip else nil
end

function FisherAnimController:Start(_hud: Instance?)
	local module = script.Parent:FindFirstChild("FishingFxController")
	if module and module:IsA("ModuleScript") then
		local ok, controller = pcall(require, module)
		fx = if ok then controller else nil
	end
	if fx and fx.TrophyReplayed then
		fx.TrophyReplayed:Connect(function()
			local f = fishers[Players.LocalPlayer]
			if f and f.heldFish and f.active then
				celebrate(f, os.clock())
			end
		end)
	end
	-- свои ответы сервера: редкость в мини-игре, попадания, отказ в забросе
	Net.Event("FishingState").OnClientEvent:Connect(function(state: any, data: any)
		local f = fishers[Players.LocalPlayer]
		if not f then
			return
		end
		local now = os.clock()
		if state == "Minigame" then
			f.rarity = if type(data) == "table" and typeof(data.Rarity) == "string" then data.Rarity else nil
		elseif state == "Zone" and now - f.tapAt > 0.6 then
			FisherAnimController.Cue("tapHit") -- (не было предсказанного рывка на это попадание)
		elseif state == "Denied" then
			cancelCast(f, now)
		end
	end)
	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(untrack)
	for _, player in Players:GetPlayers() do
		track(player)
	end
end

return FisherAnimController
