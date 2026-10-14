--!strict
--[[
	FishingService — рыбалка (Этап 2), серверная часть. Сервер решает всё сам: клиент
	(FishingController) только просит через RemoteEvent'ы, протокол — в шапке RemoteNames.

	Что делает:
	  1. Удочка. При каждом появлении персонажа кладёт в рюкзак ровно одну удочку игрока
	     (копия ReplicatedStorage.Assets.Rods.<RodId>, имя — атрибут DisplayName) и запоминает
	     этот экземпляр: рыбачить можно только им, и только когда он в руке (лежит в персонаже).
	  2. Заброс (FishingCast): игрок у точки рыбалки СВОЕЙ базы (SpotRadius по горизонтали,
	     SpotMaxHeight по вертикали), удочка в руке, нет кулдауна → состояние "Waiting",
	     поплавок летит в воду от пирса на CastDistance удочки и на FishingConfig.CastSide studs
	     правее (с пирса в лагуну): камера за спиной рыбака видит поплавок правее его головы.
	     Иначе → "Denied" с причиной и подсказкой.
	  3. Поклёвка через CastFlightTime + BiteDelay / BiteSpeed → "Bite"; не подсёк за BiteWindow
	     (+ LatencyGrace на сеть) → "Lost" late; подсёк раньше поклёвки → "Lost" early.
	  4. Подсечка (FishingHook) во время поклёвки: рыба выбирается СРАЗУ (FishingRules.RollFish),
	     стартует мини-игра "Minigame". Нажатия (FishingTap) сервер проверяет по той же стрелке
	     FishingRules.Needle, что рисует клиент: попал — "Zone" (зона переехала) или "Caught",
	     промах — "Lost" miss, не успел за MinigameTimeout — "Lost" timeout.
	  5. Поймал: атрибут FishCaught + 1, рыба в улове сессии (GetCatch), сигнал FishCaught,
	     о легендарной и мифической рыбе узнают остальные игроки (Notify с kind = редкость:
	     «Рыбак: мифическая «Рыба-дракон» ×2!», ×N — множитель мутации). Рыба выпрыгивает из воды
	     у поплавка и летит к рыбаку (это рисуют клиенты, см. атрибут FishFx ниже), а через
	     LeapTime, когда она долетела, рыба (модель HeldFish в персонаже, атрибуты FishId, Rarity,
	     Mutation, Kg, Value — для таблички над ней) появляется над головой рыбака на
	     FishingRules.HoldFishTime(редкость) секунд (её видят все).
	  6. Сам заканчивает рыбалку: персонаж умер или исчез ("died"), убрал удочку ("unequipped",
	     сразу по Tool.Unequipped),
	     отошёл дальше KeepRadius ("moved"), база освободилась ("base"), игрок смотал леску
	     (FishingStop → "stop"). Любой конец рыбалки → FishingState = "Idle" и кулдаун
	     CastCooldown до следующего заброса.

	Защита: у каждой рыбалки своя сессия с номером (Token); отложенные шаги (поклёвка,
	опоздание, тайм-аут) проверяют, что их сессия всё ещё текущая, и отменяются при её конце.
	Сеть: нажатие в мини-игре проверяется по времени клиента (в пределах MaxLag); после
	попадания нажатия, сделанные до того, как клиент увидел новую зону, не считаются.
	Запросы от клиента проверяются по типам (NaN / inf / не число), состоянию, расстоянию,
	владению базой, кулдауну; общий лимит запросов на игрока — REQUEST_BURST / REQUEST_RATE.
	Проверка активных рыбалок — раз в WATCH_INTERVAL секунд (Heartbeat), только по тем,
	кто сейчас рыбачит.

	Атрибуты Player (видят все клиенты): FishingState, BobberTarget, CastTime, RodId, FishCaught,
	FishFx — событие для эффектов в мире у всех клиентов (FishingFxController), ставится ДО того,
	как FishingState станет "Idle" (клиенты ещё видят поплавок на воде):
	  "<номер>|caught|<FishId>|<Mutation или ''>|<Rarity>" — поймал (рыба прыгает к рыбаку);
	  "<номер>|lost|<FishId или ''>|<Mutation или ''>|<Rarity или ''>" — рыба ушла
	  (до подсечки рыбы ещё нет — поля пустые). Номер растёт с каждым событием игрока.

	API для других сервисов:
	  FishingService.FishCaught                 -- Signal (player, fish: FishData)
	  FishingService:GetCatch(player) -> { FishData }   -- улов за эту игру (живая таблица:
	                                                     -- Этап 3 забирает рыбу в садок)
	  FishingService:GetRodId(player) -> string
	  FishingService:SetRod(player, rodId) -> boolean   -- сменить удочку (магазин, Этап 5)
	  FishingService:StopFishing(player, reason?)       -- закончить рыбалку ("Idle", по умолчанию "stop")
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local FishingConfig = require(Shared.Config.FishingConfig)
local MapConfig = require(Shared.Config.MapConfig)
local RodConfig = require(Shared.Config.RodConfig)
local FishingRules = require(Shared.FishingRules)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Trove = require(Shared.Util.Trove)
local Notify = require(ServerScriptService.Lib.Notify)
local BaseService = require(ServerScriptService.Services.BaseService)

type FishData = FishingRules.FishData
type Base = BaseService.Base
type Phase = "Waiting" | "Bite" | "Reeling"

-- Как часто проверять активные рыбалки (умер, убрал удочку, ушёл), секунд.
local WATCH_INTERVAL = 0.2
-- Лимит запросов рыбалки от одного игрока: запас REQUEST_BURST, пополняется REQUEST_RATE в секунду.
-- Обычная игра его не достигает; лишние запросы молча отбрасываются.
local REQUEST_BURST = 20
local REQUEST_RATE = 10
-- Нажатие «из будущего» (elapsed больше, чем прошло на сервере) честный клиент прислать
-- не может: такое нажатие игнорируется (допуск — пара кадров на округление).
local FUTURE_SLACK = 0.05
-- О каких редкостях объявлять всему серверу.
local ANNOUNCED_RARITIES = { Legendary = true, Mythic = true }

-- Тексты для игрока по коду причины — общие с клиентом (FishingConfig.Texts).
local DENIED_TEXT = FishingConfig.Texts.Denied
local LOST_TEXT = FishingConfig.Texts.Lost

type Session = {
	Token: number, -- номер сессии (отложенные шаги сверяют его)
	Phase: Phase,
	Base: Base,
	Character: Model,
	Tool: Tool,
	RodId: string,
	Thread: thread?, -- отложенный шаг: поклёвка / опоздание / тайм-аут
	-- Мини-игра (заполняется при подсечке):
	Fish: FishData?,
	U0: number,
	Speed: number,
	ZoneCenter: number,
	ZoneWidth: number,
	Hits: number,
	HitsNeeded: number,
	StartedAt: number, -- os.clock() старта мини-игры
	LastTapAt: number, -- os.clock() последнего принятого нажатия
	LastT: number, -- время мини-игры последнего принятого нажатия
}

type PlayerState = {
	Trove: Trove.Trove, -- соединения, живущие пока игрок в игре
	CharacterTrove: Trove.Trove, -- соединения текущего персонажа
	Character: Model?, -- персонаж, для которого уже выдана удочка и подключены события
	RodId: string,
	Tool: Tool?, -- выданная удочка (рыбачить можно только ею)
	Session: Session?,
	Token: number, -- номер последней начатой сессии
	CooldownUntil: number, -- os.clock(), до которого нельзя забросить снова
	Budget: number, -- лимит запросов (см. REQUEST_BURST)
	BudgetAt: number,
	Catch: { FishData },
	Caught: number, -- сколько рыб поймано за игру (атрибут FishCaught)
	HeldFish: Model?,
	HeldThread: thread?, -- уберёт рыбу над головой (или, пока рыба в прыжке, повесит её)
	FxSerial: number, -- номер последнего события FishFx
}

local FishingService = {
	FishCaught = Signal.new(),
	-- ТОЛЬКО ДЛЯ ТЕСТОВ (tests/stage2_fishing.test.luau): подменяет бросок улова, чтобы
	-- проверить мини-игру редкой рыбы. В игре всегда nil → FishingRules.RollFish.
	-- Клиент до этого поля дотянуться не может (модуль живёт только на сервере).
	RollFishForTest = nil :: ((rng: FishingRules.Rng, rodId: string?) -> FishData)?,
}

local states: { [Player]: PlayerState } = {}
local active: { [Player]: PlayerState } = {} -- игроки, которые сейчас рыбачат
local rng = Random.new()
local stateRemote = Net.Event("FishingState")

local rodAssets: Instance
local fishAssets: Instance

-- Объявлена заранее: удочка (giveRod) сматывает леску, когда её убирают из руки.
local stopSession: (player: Player, state: PlayerState, reason: string) -> ()

--------------------------------------------------------------------------------
-- Мелкие помощники
--------------------------------------------------------------------------------

local function isAlive(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return character.Parent ~= nil and humanoid ~= nil and humanoid.Health > 0
end

-- Отменяет ожидающий поток (кроме того, что выполняется сейчас).
local function cancelThread(thread: thread?)
	if thread and thread ~= coroutine.running() and coroutine.status(thread) == "suspended" then
		task.cancel(thread)
	end
end

local function send(player: Player, name: string, data: { [string]: any })
	if player.Parent == Players then
		stateRemote:FireClient(player, name, data)
	end
end

-- Число, не NaN и не бесконечность; иначе nil.
local function finiteNumber(value: unknown): number?
	if typeof(value) ~= "number" then
		return nil
	end
	local number = value :: number
	if number ~= number or number == math.huge or number == -math.huge then
		return nil
	end
	return number
end

-- Лимит запросов: true — запрос можно обработать.
local function allowRequest(state: PlayerState): boolean
	local now = os.clock()
	state.Budget = math.min(REQUEST_BURST, state.Budget + (now - state.BudgetAt) * REQUEST_RATE)
	state.BudgetAt = now
	if state.Budget < 1 then
		return false
	end
	state.Budget -= 1
	return true
end

-- Расстояние от корня персонажа до точки рыбалки: по горизонтали и по вертикали.
local function spotDistance(character: Model, spot: BasePart): (number, number)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return math.huge, math.huge
	end
	local delta = root.Position - spot.Position
	return Vector3.new(delta.X, 0, delta.Z).Magnitude, math.abs(delta.Y)
end

--------------------------------------------------------------------------------
-- Удочка в рюкзаке
--------------------------------------------------------------------------------

local function rodTemplate(rodId: string): Tool?
	local template = rodAssets:FindFirstChild(rodId)
	return if template and template:IsA("Tool") then template else nil
end

-- Убирает лишние копии удочек (инструменты с атрибутом RodId) — выданная всегда одна.
local function removeStrayRods(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("RodId") ~= nil then
			child:Destroy()
		end
	end
end

-- Кладёт удочку игрока в рюкзак, если её там (или в руке) ещё нет. Не ждёт.
local function giveRod(player: Player, state: PlayerState, character: Model?): Tool?
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return nil
	end
	local current = state.Tool
	if current and (current.Parent == backpack or (character ~= nil and current.Parent == character)) then
		return current
	end
	if current then
		current:Destroy()
		state.Tool = nil
	end
	removeStrayRods(backpack)
	if character then
		removeStrayRods(character)
	end

	local template = rodTemplate(state.RodId)
	if not template then
		warn(`[FishingService] нет ReplicatedStorage.Assets.Rods.{state.RodId}`)
		return nil
	end
	local tool = template:Clone()
	local displayName = template:GetAttribute("DisplayName")
	tool.Name = if typeof(displayName) == "string" then displayName else FishingRules.GetRod(state.RodId).Name
	-- Убрал удочку — леска сматывается сразу (наблюдатель раз в WATCH_INTERVAL не заметит
	-- быстрое «убрал и снова взял»). Соединение умирает вместе с удочкой (Destroy).
	tool.Unequipped:Connect(function()
		local session = state.Session
		if session and session.Tool == tool then
			stopSession(player, state, "unequipped")
		end
	end)
	tool.Parent = backpack
	state.Tool = tool
	return tool
end

--------------------------------------------------------------------------------
-- Рыба над головой
--------------------------------------------------------------------------------

local function weld(part0: BasePart, part1: BasePart, c0: CFrame)
	local joint = Instance.new("Weld")
	joint.Name = "HoldWeld"
	joint.Part0 = part0
	joint.Part1 = part1
	joint.C0 = c0
	joint.C1 = CFrame.identity
	joint.Parent = part1
end

local function clearHeldFish(state: PlayerState)
	cancelThread(state.HeldThread)
	state.HeldThread = nil
	local held = state.HeldFish
	state.HeldFish = nil
	if held then
		held:Destroy()
	end
end

local function fishModel(fish: FishData): Model?
	local variants = fishAssets:FindFirstChild(fish.Id)
	local model = variants and variants:FindFirstChild(fish.Mutation or "Normal")
	return if model and model:IsA("Model") and model.PrimaryPart then model else nil
end

-- Рыба (копия Assets.Fish.<Id>.<мутация>) над головой рыбака: не закреплена, без массы
-- и столкновений, приварена к голове (Weld с явным C0) — двигается вместе с персонажем.
local function holdFish(state: PlayerState, character: Model, fish: FishData)
	clearHeldFish(state)
	local head = character:FindFirstChild("Head")
	local template = fishModel(fish)
	if not head or not head:IsA("BasePart") or not template or not isAlive(character) then
		return
	end
	local model = template:Clone()
	local body = model.PrimaryPart :: BasePart
	model.Name = "HeldFish"

	-- Центр рамки рыбы встаёт над макушкой; оси модели совпадают с осями головы
	-- (голова рыбы, +X модели, смотрит вправо от персонажа).
	local pivot = model:GetPivot()
	local boxCFrame, boxSize = model:GetBoundingBox()
	local center = pivot:PointToObjectSpace(boxCFrame.Position)
	local lift = head.Size.Y / 2 + FishingConfig.HeldFishGap + boxSize.Y / 2
	local modelInHead = CFrame.new(0, lift, 0) * CFrame.new(-center)
	model:PivotTo(head.CFrame * modelInHead)

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			if part ~= body then
				weld(body, part, body.CFrame:ToObjectSpace(part.CFrame))
			end
		end
	end
	weld(head, body, head.CFrame:ToObjectSpace(body.CFrame))
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end
	-- Что за рыба — для табличек над ней у клиентов (FishingFxController).
	model:SetAttribute("FishId", fish.Id)
	model:SetAttribute("Rarity", fish.Rarity)
	model:SetAttribute("Mutation", fish.Mutation)
	model:SetAttribute("Kg", fish.Kg)
	model:SetAttribute("Value", fish.Value)
	model.Parent = character

	state.HeldFish = model
	state.HeldThread = task.delay(FishingRules.HoldFishTime(fish.Rarity), function()
		state.HeldThread = nil
		if state.HeldFish == model then
			clearHeldFish(state)
		end
	end)
end

-- Рыба в прыжке (FishingConfig.LeapTime): прежняя рыба над головой исчезает сразу, новая
-- появляется, когда долетела. Ожидание — тот же HeldThread: его отменяют выход игрока
-- и следующий улов (clearHeldFish); умер за это время — рыбы не будет (holdFish проверяет).
local function holdFishAfterLeap(state: PlayerState, character: Model, fish: FishData)
	clearHeldFish(state)
	state.HeldThread = task.delay(FishingConfig.LeapTime, function()
		state.HeldThread = nil
		holdFish(state, character, fish)
	end)
end

-- Событие для эффектов в мире у всех клиентов (атрибут FishFx, формат — в шапке).
local function broadcastFx(player: Player, state: PlayerState, kind: string, fish: FishData?)
	state.FxSerial += 1
	local id = if fish then fish.Id else ""
	local mutation = if fish then fish.Mutation or "" else ""
	local rarity = if fish then fish.Rarity else ""
	player:SetAttribute("FishFx", `{state.FxSerial}|{kind}|{id}|{mutation}|{rarity}`)
end

-- Текст объявления: «Рыбак: мифическая «Рыба-дракон» ×2!» (×N — множитель мутации).
local function announcement(player: Player, fish: FishData): string
	local rarity = FishingRules.GetRarity(fish.Rarity)
	local adjective = if rarity then rarity.NameLower else fish.Rarity
	local mutation = fish.Mutation and FishingRules.GetMutation(fish.Mutation)
	local multiplier = if mutation then ` ×{mutation.Multiplier}` else ""
	return `{player.DisplayName}: {adjective} «{FishingRules.DisplayName(fish)}»{multiplier}!`
end

-- Объявление остальным игрокам о легендарной / мифической рыбе (сам рыбак видит карточку
-- улова — тост закрыл бы её). Вид уведомления — Id редкости ("Legendary" / "Mythic"):
-- NotifyController рисует такие тосты в цветах редкости.
local function announce(player: Player, fish: FishData)
	if not ANNOUNCED_RARITIES[fish.Rarity] then
		return
	end
	local text = announcement(player, fish)
	local kind = (fish.Rarity :: any) :: Notify.Kind
	for _, other in Players:GetPlayers() do
		if other ~= player then
			Notify.Send(other, text, kind)
		end
	end
end

--------------------------------------------------------------------------------
-- Сессия рыбалки
--------------------------------------------------------------------------------

local function isCurrent(state: PlayerState, session: Session): boolean
	return state.Session == session and session.Token == state.Token
end

-- Ставит следующий отложенный шаг сессии (предыдущий отменяется).
local function schedule(state: PlayerState, session: Session, delay: number, step: () -> ())
	cancelThread(session.Thread)
	session.Thread = task.delay(delay, function()
		if isCurrent(state, session) then
			session.Thread = nil
			step()
		end
	end)
end

-- Заканчивает текущую рыбалку: состояние "Idle", кулдаун, событие клиенту.
local function endSession(player: Player, state: PlayerState, event: string, data: { [string]: any })
	local session = state.Session
	if not session then
		return
	end
	state.Session = nil
	active[player] = nil
	cancelThread(session.Thread)
	session.Thread = nil
	state.CooldownUntil = os.clock() + FishingConfig.CastCooldown
	player:SetAttribute("FishingState", "Idle")
	send(player, event, data)
end

local function lose(player: Player, state: PlayerState, reason: string)
	local session = state.Session
	if not session then
		return
	end
	broadcastFx(player, state, "lost", session.Fish) -- до "Idle": поплавок ещё на воде
	endSession(player, state, "Lost", { Reason = reason, Text = LOST_TEXT[reason] or "" })
end

local function stop(player: Player, state: PlayerState, reason: string)
	endSession(player, state, "Idle", { Reason = reason })
end
stopSession = stop

local function catch(player: Player, state: PlayerState, session: Session)
	local fish = session.Fish :: FishData
	state.Caught += 1
	table.insert(state.Catch, fish)
	player:SetAttribute("FishCaught", state.Caught)
	broadcastFx(player, state, "caught", fish) -- до "Idle": рыба прыгает от поплавка на воде
	endSession(player, state, "Caught", { Fish = fish, Total = state.Caught })
	holdFishAfterLeap(state, session.Character, fish)
	announce(player, fish)
	FishingService.FishCaught:Fire(player, fish)
end

-- Точка в воде перед пирсом (−Z базы смотрит в лагуну) на дальности заброса удочки и чуть
-- правее (FishingConfig.CastSide: из-за спины рыбака поплавок виден правее его головы).
local function castTarget(base: Base, castDistance: number): Vector3
	local pivot = base.Model:GetPivot()
	local forward = Vector3.new(pivot.LookVector.X, 0, pivot.LookVector.Z).Unit
	local right = Vector3.new(pivot.RightVector.X, 0, pivot.RightVector.Z).Unit
	local side = rng:NextNumber(FishingConfig.CastSide.Min, FishingConfig.CastSide.Max)
	local point = base.FishingSpot.Position + forward * castDistance + right * side
	return Vector3.new(point.X, MapConfig.WaterTop, point.Z)
end

local function startMinigame(player: Player, state: PlayerState, session: Session)
	local roll: (FishingRules.Rng, string?) -> FishData = FishingService.RollFishForTest or FishingRules.RollFish
	local fish = roll(rng, session.RodId)
	local rule = FishingRules.GetMinigameRule(fish.Rarity)
	session.Phase = "Reeling"
	session.Fish = fish
	session.U0 = rng:NextNumber(0, 2)
	session.Speed = rule.Speed
	session.ZoneWidth = FishingRules.ZoneWidth(fish.Rarity, session.RodId)
	session.ZoneCenter =
		FishingRules.PickZoneCenter(rng, session.ZoneWidth, FishingRules.Needle(session.U0, session.Speed, 0))
	session.Hits = 0
	session.HitsNeeded = rule.Hits
	session.StartedAt = os.clock()
	-- Подсечка считается первым нажатием: случайное двойное нажатие сразу после неё
	-- (раньше TapInterval) не превращается в промах.
	session.LastTapAt = session.StartedAt
	session.LastT = 0

	player:SetAttribute("FishingState", "Reeling")
	send(player, "Minigame", {
		Rarity = fish.Rarity,
		U0 = session.U0,
		Speed = session.Speed,
		ZoneCenter = session.ZoneCenter,
		ZoneWidth = session.ZoneWidth,
		Hits = 0,
		HitsNeeded = session.HitsNeeded,
		Timeout = FishingConfig.MinigameTimeout,
	})
	schedule(state, session, FishingConfig.MinigameTimeout + FishingConfig.LatencyGrace, function()
		lose(player, state, "timeout")
	end)
end

local function startBite(player: Player, state: PlayerState, session: Session)
	session.Phase = "Bite"
	player:SetAttribute("FishingState", "Bite")
	send(player, "Bite", { Window = FishingConfig.BiteWindow })
	schedule(state, session, FishingConfig.BiteWindow + FishingConfig.LatencyGrace, function()
		lose(player, state, "late")
	end)
end

local function startSession(player: Player, state: PlayerState, base: Base, character: Model, tool: Tool)
	local rod = FishingRules.GetRod(state.RodId)
	state.Token += 1
	local session: Session = {
		Token = state.Token,
		Phase = "Waiting",
		Base = base,
		Character = character,
		Tool = tool,
		RodId = rod.Id,
		Thread = nil,
		Fish = nil,
		U0 = 0,
		Speed = 0,
		ZoneCenter = 0.5,
		ZoneWidth = 0,
		Hits = 0,
		HitsNeeded = 1,
		StartedAt = 0,
		LastTapAt = 0,
		LastT = 0,
	}
	state.Session = session
	active[player] = state

	local target = castTarget(base, rod.CastDistance)
	-- Сначала данные поплавка, потом состояние: клиенты реагируют на смену FishingState.
	player:SetAttribute("BobberTarget", target)
	player:SetAttribute("CastTime", Workspace:GetServerTimeNow())
	player:SetAttribute("FishingState", "Waiting")
	send(player, "Waiting", { Target = target, FlightTime = FishingConfig.CastFlightTime })

	local delay = FishingConfig.CastFlightTime
		+ rng:NextNumber(FishingConfig.BiteDelay.Min, FishingConfig.BiteDelay.Max) / rod.BiteSpeed
	schedule(state, session, delay, function()
		startBite(player, state, session)
	end)
end

-- Почему нельзя забросить (причина для "Denied") или nil, если можно.
local function castProblem(player: Player, state: PlayerState): string?
	if state.Session then
		return "busy"
	end
	if os.clock() < state.CooldownUntil then
		return "cooldown"
	end
	local base = BaseService:GetBase(player)
	if not base or base.Owner ~= player then
		return "nobase"
	end
	local character = player.Character
	local tool = state.Tool
	if not character or not isAlive(character) or not tool or tool.Parent ~= character then
		return "norod"
	end
	local horizontal, vertical = spotDistance(character, base.FishingSpot)
	if horizontal > FishingConfig.SpotRadius or vertical > FishingConfig.SpotMaxHeight then
		return "far"
	end
	return nil
end

-- Проверка активной рыбалки (раз в WATCH_INTERVAL и перед подсечкой / нажатием):
-- персонаж жив, удочка в руке, база своя, игрок не ушёл от точки рыбалки.
-- false — рыбалка закончилась.
local function checkSession(player: Player, state: PlayerState, session: Session): boolean
	local character = session.Character
	local reason: string? = nil
	if player.Character ~= character or not isAlive(character) then
		reason = "died"
	elseif session.Tool.Parent ~= character then
		reason = "unequipped"
	elseif session.Base.Owner ~= player then
		reason = "base"
	else
		local horizontal, vertical = spotDistance(character, session.Base.FishingSpot)
		if horizontal > FishingConfig.KeepRadius or vertical > FishingConfig.KeepRadius then
			reason = "moved"
		end
	end
	if reason then
		stop(player, state, reason)
		return false
	end
	return true
end

--------------------------------------------------------------------------------
-- Запросы клиента
--------------------------------------------------------------------------------

local function onCast(player: Player)
	local state = states[player]
	if not state or not allowRequest(state) then
		return
	end
	local problem = castProblem(player, state)
	if problem then
		send(player, "Denied", { Reason = problem, Text = DENIED_TEXT[problem] or "" })
		return
	end
	-- castProblem уже проверил, что всё это есть.
	local base = BaseService:GetBase(player) :: Base
	startSession(player, state, base, player.Character :: Model, state.Tool :: Tool)
end

local function onHook(player: Player)
	local state = states[player]
	if not state or not allowRequest(state) then
		return
	end
	local session = state.Session
	if not session or not checkSession(player, state, session) then
		return
	end
	if session.Phase == "Waiting" then
		lose(player, state, "early")
	elseif session.Phase == "Bite" then
		startMinigame(player, state, session)
	end
end

-- Время мини-игры, по которому проверяется нажатие, или nil — нажатие не считается.
-- Клиент присылает elapsed по своим часам с получения "Minigame"; сервер принимает его
-- не позже своего времени и не раньше чем на MaxLag (см. FishingConfig).
local function tapTime(session: Session, elapsed: number, now: number): number?
	local serverElapsed = now - session.StartedAt
	if elapsed < 0 or elapsed > serverElapsed + FUTURE_SLACK then
		return nil -- отрицательное или «из будущего»: так честный клиент не присылает
	end
	local t = math.clamp(elapsed, serverElapsed - FishingConfig.MaxLag, serverElapsed)
	if t < session.LastT or t > FishingConfig.MinigameTimeout then
		return nil -- назад во времени или после конца мини-игры
	end
	return t
end

-- Нажатие в момент t мини-игры: попал — зона переезжает (или рыба поймана), мимо — рыба уходит.
-- now — когда нажатие пришло на сервер.
local function applyTap(player: Player, state: PlayerState, session: Session, t: number, now: number)
	session.LastT = t
	local position = FishingRules.Needle(session.U0, session.Speed, t)
	if not FishingRules.IsHit(position, session.ZoneCenter, session.ZoneWidth) then
		if session.Hits == 0 and t < FishingConfig.HookTapGrace then
			return -- второй тап двойного нажатия «Подсечь»: не промах (см. FishingConfig)
		end
		lose(player, state, "miss")
		return
	end
	session.Hits += 1
	if session.Hits >= session.HitsNeeded then
		catch(player, state, session)
		return
	end
	-- Зона переезжает сейчас, а клиент увидит её только через пинг: до этого момента он
	-- рисует старую зону. Его время мини-игры, когда придёт "Zone", ≈ серверное время сейчас
	-- (оба сообщения идут к нему с одной задержкой). Нажатия раньше этого момента целились
	-- в старую зону — они не считаются вовсе (ни попаданием, ни промахом), и новая зона
	-- ставится подальше от стрелки, какой её увидит клиент.
	local seenAt = now - session.StartedAt
	session.LastT = math.max(t, seenAt)
	local needleSeen = FishingRules.Needle(session.U0, session.Speed, seenAt)
	session.ZoneCenter = FishingRules.PickZoneCenter(rng, session.ZoneWidth, needleSeen, session.ZoneCenter)
	send(player, "Zone", { ZoneCenter = session.ZoneCenter, Hits = session.Hits })
end

local function onTap(player: Player, rawElapsed: unknown)
	local state = states[player]
	if not state or not allowRequest(state) then
		return
	end
	local session = state.Session
	local elapsed = finiteNumber(rawElapsed)
	if not session or session.Phase ~= "Reeling" or not elapsed or not checkSession(player, state, session) then
		return
	end
	local now = os.clock()
	if now - session.LastTapAt < FishingConfig.TapInterval then
		return -- чаще TapInterval не принимаем
	end
	local t = tapTime(session, elapsed, now)
	if t then
		session.LastTapAt = now
		applyTap(player, state, session, t, now)
	end
end

local function onStop(player: Player)
	local state = states[player]
	if state and allowRequest(state) and state.Session then
		stop(player, state, "stop")
	end
end

--------------------------------------------------------------------------------
-- Игроки и персонажи
--------------------------------------------------------------------------------

local function onCharacterRemoving(player: Player, state: PlayerState, character: Model)
	local session = state.Session
	if session and session.Character == character then
		stop(player, state, "died")
	end
	if state.Character == character then
		state.Character = nil
		state.CharacterTrove:Clean()
	end
end

local function onCharacterAdded(player: Player, state: PlayerState, character: Model)
	if state.Character == character then
		return -- уже обработан (персонаж был до подписки + событие CharacterAdded)
	end
	state.Character = character
	state.CharacterTrove:Clean()
	local session = state.Session
	if session and session.Character ~= character then
		stop(player, state, "died")
	end

	-- Рюкзак пересоздаётся при появлении персонажа: кладём удочку, когда он готов.
	if not player:FindFirstChildOfClass("Backpack") then
		player:WaitForChild("Backpack", 5)
	end
	if states[player] ~= state or player.Character ~= character then
		return -- пока ждали, игрок вышел или персонаж сменился
	end
	giveRod(player, state, character)

	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	if states[player] ~= state or state.Character ~= character then
		return
	end
	state.CharacterTrove:Connect(humanoid.Died, function()
		local current = state.Session
		if current and current.Character == character then
			stop(player, state, "died")
		end
	end)
end

local function onPlayerAdded(player: Player)
	if states[player] then
		return -- уже обработан (цикл по уже вошедшим игрокам + событие PlayerAdded)
	end
	local state: PlayerState = {
		Trove = Trove.new(),
		CharacterTrove = Trove.new(),
		Character = nil,
		RodId = RodConfig.StartRod,
		Tool = nil,
		Session = nil,
		Token = 0,
		CooldownUntil = 0,
		Budget = REQUEST_BURST,
		BudgetAt = os.clock(),
		Catch = {},
		Caught = 0,
		HeldFish = nil,
		HeldThread = nil,
		FxSerial = 0,
	}
	states[player] = state
	state.Trove:Add(state.CharacterTrove)

	player:SetAttribute("RodId", state.RodId)
	player:SetAttribute("FishCaught", 0)
	player:SetAttribute("FishingState", "Idle")

	state.Trove:Connect(player.CharacterAdded, function(character: Model)
		onCharacterAdded(player, state, character)
	end)
	state.Trove:Connect(player.CharacterRemoving, function(character: Model)
		onCharacterRemoving(player, state, character)
	end)
	-- Если движок пересоздал рюкзак уже после CharacterAdded, удочка пропала бы вместе со
	-- старым рюкзаком — кладём её в новый.
	state.Trove:Connect(player.ChildAdded, function(child: Instance)
		local character = state.Character
		if child:IsA("Backpack") and character and player.Character == character then
			task.defer(function()
				if states[player] == state and state.Character == character and isAlive(character) then
					giveRod(player, state, character)
				end
			end)
		end
	end)
	local character = player.Character
	if character then
		task.spawn(onCharacterAdded, player, state, character)
	end
end

local function onPlayerRemoving(player: Player)
	local state = states[player]
	if not state then
		return
	end
	states[player] = nil
	active[player] = nil

	local session = state.Session
	state.Session = nil
	if session then
		cancelThread(session.Thread)
		session.Thread = nil
	end
	clearHeldFish(state)
	local tool = state.Tool
	state.Tool = nil
	if tool then
		tool:Destroy()
	end
	state.Trove:Clean()
end

-- Раз в WATCH_INTERVAL проверяет только тех, кто сейчас рыбачит.
local function startWatcher()
	local sinceCheck = 0
	RunService.Heartbeat:Connect(function(dt: number)
		sinceCheck += dt
		if sinceCheck < WATCH_INTERVAL or next(active) == nil then
			return
		end
		sinceCheck = 0
		-- Копия: проверка может закончить рыбалку (убрать игрока из active).
		for player, state in table.clone(active) do
			local session = state.Session
			if session then
				checkSession(player, state, session)
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- Публичное API
--------------------------------------------------------------------------------

function FishingService:GetCatch(player: Player): { FishData }
	local state = states[player]
	return if state then state.Catch else {}
end

function FishingService:GetRodId(player: Player): string
	local state = states[player]
	return if state then state.RodId else RodConfig.StartRod
end

-- Сменить удочку: текущая рыбалка заканчивается, старая удочка заменяется новой
-- (если старая была в руке — новая тоже окажется в руке).
function FishingService:SetRod(player: Player, rodId: string): boolean
	local state = states[player]
	if not state or FishingRules.GetRod(rodId).Id ~= rodId or not rodTemplate(rodId) then
		return false
	end
	if state.Session then
		stop(player, state, "unequipped")
	end
	local character = player.Character
	local old = state.Tool
	local wasEquipped = old ~= nil and character ~= nil and old.Parent == character
	if old then
		old:Destroy()
		state.Tool = nil
	end
	state.RodId = rodId
	player:SetAttribute("RodId", rodId)
	local tool = if character and isAlive(character) then giveRod(player, state, character) else nil
	if tool and wasEquipped then
		tool.Parent = character
	end
	return true
end

-- Закончить рыбалку игрока (если он рыбачит): "Idle" с причиной reason.
function FishingService:StopFishing(player: Player, reason: string?)
	local state = states[player]
	if state and state.Session then
		stop(player, state, reason or "stop")
	end
end

--------------------------------------------------------------------------------
-- Жизненный цикл сервиса
--------------------------------------------------------------------------------

function FishingService:Init()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local rods = assets and assets:FindFirstChild("Rods")
	local fish = assets and assets:FindFirstChild("Fish")
	assert(rods and fish, "[FishingService] нет ReplicatedStorage.Assets.Rods / Assets.Fish")
	rodAssets = rods
	fishAssets = fish
	for _, rod in RodConfig.Rods do
		assert(rodTemplate(rod.Id), `[FishingService] нет удочки Assets.Rods.{rod.Id} (Tool)`)
	end
end

function FishingService:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	BaseService.BaseReleased:Connect(function(player: Player, base: Base)
		local state = states[player]
		local session = state and state.Session
		if state and session and session.Base == base then
			stop(player, state, "base")
		end
	end)

	Net.Event("FishingCast").OnServerEvent:Connect(onCast)
	Net.Event("FishingHook").OnServerEvent:Connect(onHook)
	Net.Event("FishingTap").OnServerEvent:Connect(onTap)
	Net.Event("FishingStop").OnServerEvent:Connect(onStop)

	startWatcher()
end

return FishingService
