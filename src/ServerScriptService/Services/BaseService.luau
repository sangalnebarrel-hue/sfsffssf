--!strict
--[[
	BaseService — базы игроков (Этап 1).

	Что делает:
	  1. При старте сервера клонирует шаблон ServerStorage.BaseTemplate в каждый слот
	     Workspace.Map.BaseSlots (8 штук) и красит базу в свой цвет из BaseConfig.Colors.
	     Красятся детали шаблона с атрибутом Accent = true (флаг, крыши, навесы и т.д.), а детали
	     с WallTone = true получают тон стен базы (BaseConfig.WallTones, оттенок — WallShade);
	     числовой атрибут AccentShade (от -1 до 1) даёт оттенок: > 0 — светлее (к белому),
	     < 0 — темнее (к чёрному). Все TextLabel с именами OwnerLabel / BaseLabel (табличка над
	     флагом, вывеска на воротах и т.д.) показывают владельца и название базы.
	  2. Выдаёт игроку свободную базу при входе и освобождает её при выходе.
	     Если свободных баз нет — игрок ждёт на хабе в очереди (первым пришёл — первым получил).
	  3. Сам спаунит персонажей (Players.CharacterAutoLoads = false): персонаж появляется
	     на площадке своей базы, после смерти — снова там через BaseConfig.RespawnDelay секунд.
	     Если создать персонажа не удалось — пробует ещё несколько раз.
	  4. Обрабатывает кнопку «Домой» (RemoteEvent RequestHome) с серверным кулдауном.

	Состояние для клиентов (атрибуты реплицируются автоматически):
	  Player: BaseIndex (0 — ждёт базу), BaseColorName, BaseColor
	  Модель базы (Workspace.Bases.Base_N): BaseIndex, ColorId, ColorName, Color, OwnerUserId (0 — свободна), OwnerName

	API для других сервисов:
	  BaseService:GetBase(player) -> Base?
	  BaseService:GetBases() -> { Base }
	  BaseService:GetBaseFromInstance(instance) -> Base?   -- по любой детали внутри базы
	  BaseService:GetSpawnCFrame(base) -> CFrame
	  BaseService:TeleportHome(player) -> boolean
	  BaseService:RespawnPlayer(player)                     -- пересоздать персонажа (всегда через этот метод!)
	  BaseService.BaseAssigned  -- Signal (player, base)
	  BaseService.BaseReleased  -- Signal (player, base)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local BaseConfig = require(Shared.Config.BaseConfig)
local Cooldown = require(Shared.Util.Cooldown)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Trove = require(Shared.Util.Trove)
local Notify = require(ServerScriptService.Lib.Notify)

-- Сколько раз пробовать создать персонажа, если LoadCharacterAsync упал, и с какой паузой.
local SPAWN_ATTEMPTS = 5
local SPAWN_RETRY_DELAY = 2
-- Сервер прощает чуть-чуть кулдауна «Домой»: из-за задержки сети нажатие сразу после того,
-- как кнопка снова стала активной у клиента, может прийти на сервер раньше 5 секунд.
local HOME_COOLDOWN_SLACK = 0.5

export type Base = {
	Index: number,
	Model: Model,
	ColorId: string,
	ColorName: string,
	Color: Color3,
	Owner: Player?,
	-- Ключевые детали базы (для следующих этапов: рыбалка, садок, кража).
	SpawnPad: BasePart,
	FishingSpot: BasePart,
	Tank: Model,
	TankGlass: BasePart,
	TankPromptAttachment: Attachment,
	AlarmLamp: BasePart,
	Dog: Model,
	OwnerLabel: TextLabel, -- табличка над флагом (обязательная)
	OwnerLabels: { TextLabel }, -- все надписи с именем владельца (флаг, ворота, ...)
}

type PlayerState = {
	Base: Base?,
	Trove: Trove.Trove, -- соединения, живущие пока игрок в игре
	CharacterTrove: Trove.Trove, -- соединения текущего персонажа
	Spawning: boolean, -- сейчас идёт LoadCharacterAsync
	SpawnPending: boolean, -- пока шла загрузка, попросили ещё одно возрождение
	SpawnFailures: number,
	RespawnThread: thread?, -- отложенное возрождение / повтор спауна
}

local BaseService = {
	BaseAssigned = Signal.new(),
	BaseReleased = Signal.new(),
}

local bases: { Base } = {}
local baseByModel: { [Model]: Base } = {}
local states: { [Player]: PlayerState } = {}
local waitQueue: { Player } = {} -- игроки без базы, по порядку входа
local homeCooldown = Cooldown.new(math.max(0, BaseConfig.HomeCooldown - HOME_COOLDOWN_SLACK))
local rng = Random.new()

local WHITE = Color3.new(1, 1, 1)

--------------------------------------------------------------------------------
-- Создание баз
--------------------------------------------------------------------------------

-- Находит обязательную деталь шаблона по пути и проверяет её класс.
local function findRequired(root: Instance, path: { string }, className: string): any
	local current: Instance = root
	for _, name in path do
		local child = current:FindFirstChild(name)
		if not child then
			error(`[BaseService] в {root:GetFullName()} нет {table.concat(path, ".")}`)
		end
		current = child
	end
	if not current:IsA(className) then
		error(`[BaseService] {current:GetFullName()} должен быть {className}, а это {current.ClassName}`)
	end
	return current
end

local function getSlots(): { BasePart }
	local map = Workspace:FindFirstChild("Map")
	local slotFolder = map and map:FindFirstChild("BaseSlots")
	assert(slotFolder, "[BaseService] нет Workspace.Map.BaseSlots")

	local slots: { BasePart } = {}
	for _, child in slotFolder:GetChildren() do
		if child:IsA("BasePart") and typeof(child:GetAttribute("Index")) == "number" then
			table.insert(slots, child)
		end
	end
	table.sort(slots, function(a, b)
		return (a:GetAttribute("Index") :: number) < (b:GetAttribute("Index") :: number)
	end)

	-- Отладка очереди: BaseConfig.MaxBases ограничивает число баз.
	local maxBases = BaseConfig.MaxBases
	if maxBases and maxBases < #slots then
		warn(
			`[BaseService] BaseConfig.MaxBases = {maxBases}: создаётся только {maxBases} баз (режим отладки)`
		)
		for _ = maxBases + 1, #slots do
			table.remove(slots)
		end
	end
	if #slots > #BaseConfig.Colors then
		warn(
			`[BaseService] слотов ({#slots}) больше, чем цветов в BaseConfig.Colors ({#BaseConfig.Colors}) — цвета повторятся`
		)
	end
	return slots
end

local function updateSign(base: Base)
	local owner = base.Owner
	local text = if owner then owner.DisplayName else "Свободно"
	for _, label in base.OwnerLabels do
		label.Text = text
	end
end

-- Цвет акцентной детали: цвет базы, осветлённый (AccentShade > 0, к белому) или затемнённый
-- (< 0). Затемняем через HSV, а не к чёрному: яркость ниже, насыщенность чуть выше, тёплые тона
-- уходят к красному — жёлтый становится янтарным, а не оливковым, красный — не бордовым.
-- (Та же формула в tools/preview/export_parts.luau, tools/builder/BaseTemplate.luau и тестах.)
local function shadeColor(color: Color3, shade: any): Color3
	if typeof(shade) ~= "number" or shade == 0 then
		return color
	end
	local amount = math.clamp(math.abs(shade), 0, 1)
	if shade > 0 then
		return color:Lerp(WHITE, amount)
	end
	local h, s, v = color:ToHSV()
	if h > 0.02 and h < 0.2 and amount > 0.3 then
		h -= 0.04 * (amount - 0.3) / 0.7 -- light shades keep their hue (yellow stays yellow)
	end
	return Color3.fromHSV(h, math.min(1, s * (1 + 0.15 * amount)), v * (1 - 0.6 * amount))
end

local function createBase(template: Model, slot: BasePart, index: number, parent: Instance): Base
	local colors = BaseConfig.Colors
	local colorDef = colors[(index - 1) % #colors + 1]
	local wallTones = BaseConfig.WallTones
	local wallTone = wallTones[(index - 1) % #wallTones + 1]

	local model = template:Clone()
	model.Name = `Base_{index}`
	model:PivotTo(slot.CFrame)

	-- Красим акцентные детали в цвет базы (с оттенком) и собираем все надписи базы.
	local ownerLabels: { TextLabel } = {}
	local baseLabels: { TextLabel } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("Accent") == true then
			local shade = descendant:GetAttribute("AccentShade")
			if typeof(shade) == "number" and shade < 0 then
				shade *= colorDef.RoofShadeScale or 1
			end
			descendant.Color = shadeColor(colorDef.Color, shade)
		elseif descendant:IsA("BasePart") and descendant:GetAttribute("WallTone") == true then
			descendant.Color = shadeColor(wallTone, descendant:GetAttribute("WallShade"))
		elseif descendant:IsA("TextLabel") then
			if descendant.Name == "OwnerLabel" then
				table.insert(ownerLabels, descendant)
			elseif descendant.Name == "BaseLabel" then
				table.insert(baseLabels, descendant)
			end
		end
	end

	model:SetAttribute("BaseIndex", index)
	model:SetAttribute("ColorId", colorDef.Id)
	model:SetAttribute("ColorName", colorDef.Name)
	model:SetAttribute("Color", colorDef.Color)
	model:SetAttribute("OwnerUserId", 0)
	model:SetAttribute("OwnerName", "")

	local base: Base = {
		Index = index,
		Model = model,
		ColorId = colorDef.Id,
		ColorName = colorDef.Name,
		Color = colorDef.Color,
		Owner = nil,
		SpawnPad = findRequired(model, { "SpawnPad" }, "BasePart"),
		FishingSpot = findRequired(model, { "FishingSpot" }, "BasePart"),
		Tank = findRequired(model, { "Tank" }, "Model"),
		TankGlass = findRequired(model, { "Tank", "Glass" }, "BasePart"),
		TankPromptAttachment = findRequired(model, { "Tank", "Glass", "PromptAttachment" }, "Attachment"),
		AlarmLamp = findRequired(model, { "Alarm", "Lamp" }, "BasePart"),
		Dog = findRequired(model, { "Dog" }, "Model"),
		OwnerLabel = findRequired(model, { "Flag", "Pole", "SignAttachment", "OwnerSign", "OwnerLabel" }, "TextLabel"),
		OwnerLabels = ownerLabels,
	}

	-- Табличка над флагом обязательна; остальные надписи (ворота и т.д.) — сколько есть.
	findRequired(model, { "Flag", "Pole", "SignAttachment", "OwnerSign", "BaseLabel" }, "TextLabel")
	for _, baseLabel in baseLabels do
		baseLabel.Text = `{colorDef.Name} база`
		baseLabel.TextColor3 = colorDef.Color
	end
	updateSign(base)

	model.Parent = parent
	return base
end

--------------------------------------------------------------------------------
-- Спаун персонажей
--------------------------------------------------------------------------------

function BaseService:GetSpawnCFrame(base: Base): CFrame
	local pad = base.SpawnPad
	return pad.CFrame * CFrame.new(0, pad.Size.Y / 2 + BaseConfig.SpawnHeight, 0)
end

local function isAlive(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- Запоминает поток возрождения/повтора; предыдущий ожидающий поток отменяется,
-- чтобы одновременно жил только один (иначе игрок мог бы возродиться дважды).
local function setRespawnThread(state: PlayerState, thread: thread?)
	local previous = state.RespawnThread
	if previous and previous ~= coroutine.running() and coroutine.status(previous) == "suspended" then
		task.cancel(previous)
	end
	state.RespawnThread = thread
end

-- Сбрасывает поле, только если там всё ещё наш поток (а не уже более новый).
local function clearRespawnThread(state: PlayerState)
	if state.RespawnThread == coroutine.running() then
		state.RespawnThread = nil
	end
end

-- Ставит живого персонажа на площадку его базы (если база есть).
local function placeCharacter(player: Player, character: Model)
	local state = states[player]
	if not state or not state.Base then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 5)
	-- Пока ждали, игрок мог выйти, умереть и возродиться или потерять базу.
	local base = state.Base
	if not root or not base or states[player] ~= state or player.Character ~= character or not character.Parent then
		return
	end
	if not isAlive(character) then
		return -- мёртвое тело не двигаем: новый персонаж появится на базе сам
	end
	character:PivotTo(BaseService:GetSpawnCFrame(base))
end

-- То же, но для персонажа, который движок ещё не поставил в мир: CharacterAdded приходит
-- ДО того, как персонаж окажется в Workspace и будет перенесён на SpawnLocation.
-- Ждём появления в Workspace, даём движку кадр закончить спаун и только потом переносим.
local function placeWhenReady(player: Player, character: Model)
	if not character:IsDescendantOf(Workspace) then
		local deadline = os.clock() + 10
		while not character:IsDescendantOf(Workspace) and os.clock() < deadline do
			task.wait(0.1)
		end
		task.wait()
	end
	placeCharacter(player, character)
end

-- LoadCharacterAsync — новое имя LoadCharacter (старое помечено устаревшим).
-- Если движок старый и нового метода нет — используем старый.
local function loadCharacter(player: Player): (boolean, any)
	local ok, err = pcall(function()
		player:LoadCharacterAsync()
		return nil
	end)
	if not ok and string.find(tostring(err), "not a valid member", 1, true) then
		ok, err = pcall(function()
			(player :: any):LoadCharacter()
			return nil
		end)
	end
	return ok, err
end

-- Создаёт персонажа (Players.CharacterAutoLoads выключен) и ставит его на базу.
local function spawnCharacter(player: Player)
	local state = states[player]
	if not state or player.Parent ~= Players then
		return
	end
	if state.Spawning then
		state.SpawnPending = true -- выполним, когда закончится текущая загрузка
		return
	end

	state.Spawning = true
	state.SpawnPending = false
	-- Ждёт, пока персонаж появится. Без базы он встанет на HubSpawn в центре.
	local ok, err = loadCharacter(player)
	state.Spawning = false

	if states[player] ~= state or player.Parent ~= Players then
		return -- игрок вышел, пока персонаж создавался (ошибка в этом случае ожидаема)
	end

	if not ok then
		state.SpawnFailures += 1
		warn(
			`[BaseService] LoadCharacter({player.Name}) не удался (попытка {state.SpawnFailures}): {err}`
		)
		if state.SpawnFailures >= SPAWN_ATTEMPTS then
			player:Kick(
				"Не получилось создать персонажа. Перезайди, пожалуйста."
			)
			return
		end
		-- Повторяем, только если за это время персонажа не создали другим путём.
		local failedWith = player.Character
		setRespawnThread(
			state,
			task.delay(SPAWN_RETRY_DELAY, function()
				clearRespawnThread(state)
				if states[player] == state and player.Character == failedWith then
					spawnCharacter(player)
				end
			end)
		)
		return
	end
	state.SpawnFailures = 0

	local character = player.Character
	if character then
		placeWhenReady(player, character)
	end

	-- Во время загрузки кто-то попросил возрождение: нужно, только если новый персонаж уже мёртв.
	if state.SpawnPending then
		state.SpawnPending = false
		if not character or not isAlive(character) then
			spawnCharacter(player)
		end
	end
end

local function scheduleRespawn(player: Player, state: PlayerState, character: Model)
	setRespawnThread(
		state,
		task.delay(BaseConfig.RespawnDelay, function()
			clearRespawnThread(state)
			-- Возрождаем, только если это всё ещё тот же игрок и тот же (мёртвый) персонаж.
			if states[player] == state and player.Character == character then
				spawnCharacter(player)
			end
		end)
	)
end

local function onCharacterAdded(player: Player, state: PlayerState, character: Model)
	state.CharacterTrove:Clean()

	-- Персонажа создал не spawnCharacter (например, кто-то вызвал LoadCharacterAsync сам) —
	-- всё равно переносим его на базу, когда движок закончит спаун.
	-- (Если идёт spawnCharacter, он сам поставит player.Character на базу после загрузки.)
	if not state.Spawning then
		state.CharacterTrove:Add(task.spawn(function()
			if character:IsDescendantOf(Workspace) then
				task.wait() -- уже в мире: даём движку закончить перенос на SpawnLocation
			end
			placeWhenReady(player, character)
		end))
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	if states[player] ~= state or player.Character ~= character then
		return -- пока ждали Humanoid, игрок вышел или персонаж сменился
	end
	state.CharacterTrove:Connect(humanoid.Died, function()
		scheduleRespawn(player, state, character)
	end)
end

--------------------------------------------------------------------------------
-- Выдача и освобождение баз
--------------------------------------------------------------------------------

local function pickFreeBase(): Base?
	local free: { Base } = {}
	for _, base in bases do
		if base.Owner == nil then
			table.insert(free, base)
		end
	end
	if #free == 0 then
		return nil
	end
	if BaseConfig.RandomAssignment then
		return free[rng:NextInteger(1, #free)]
	end
	return free[1]
end

local function assignBase(player: Player, state: PlayerState, base: Base)
	base.Owner = player
	state.Base = base

	base.Model:SetAttribute("OwnerUserId", player.UserId)
	base.Model:SetAttribute("OwnerName", player.DisplayName)
	-- Сначала цвет и имя, потом индекс: клиент обновляет плашку по смене BaseIndex.
	player:SetAttribute("BaseColorName", base.ColorName)
	player:SetAttribute("BaseColor", base.Color)
	player:SetAttribute("BaseIndex", base.Index)
	updateSign(base)

	BaseService.BaseAssigned:Fire(player, base)
end

-- Раздаёт свободные базы игрокам из очереди (по порядку входа).
local function serveQueue()
	while #waitQueue > 0 do
		local base = pickFreeBase()
		if not base then
			return
		end
		local player = table.remove(waitQueue, 1) :: Player
		local state = states[player]
		if state and not state.Base and player.Parent == Players then
			-- Уведомление «Тебе досталась Лазурная база!» (в цветах базы) показывает сам клиент
			-- (HudController: плашка перешла из «Ждём базу…» в базу).
			assignBase(player, state, base)
			local character = player.Character
			if character then
				task.spawn(placeCharacter, player, character)
			else
				task.spawn(spawnCharacter, player)
			end
		end
	end
end

local function releaseBase(player: Player, state: PlayerState)
	local base = state.Base
	if not base then
		return
	end
	state.Base = nil
	base.Owner = nil

	base.Model:SetAttribute("OwnerUserId", 0)
	base.Model:SetAttribute("OwnerName", "")
	updateSign(base)

	BaseService.BaseReleased:Fire(player, base)
	-- Отдаём базу ждущему игроку чуть позже, чтобы обработчики BaseReleased успели прибраться.
	-- Новые игроки в это время не обгонят очередь (см. onPlayerAdded).
	task.defer(serveQueue)
end

local function onPlayerAdded(player: Player)
	if states[player] then
		return -- уже обработан (цикл по уже вошедшим игрокам + событие PlayerAdded)
	end

	local state: PlayerState = {
		Base = nil,
		Trove = Trove.new(),
		CharacterTrove = Trove.new(),
		Spawning = false,
		SpawnPending = false,
		SpawnFailures = 0,
		RespawnThread = nil,
	}
	states[player] = state
	state.Trove:Add(state.CharacterTrove)

	state.Trove:Connect(player.CharacterAdded, function(character: Model)
		onCharacterAdded(player, state, character)
	end)
	state.Trove:Connect(player.CharacterRemoving, function()
		state.CharacterTrove:Clean()
	end)

	-- Свободную базу берём, только если никто не ждёт в очереди — иначе встаём в конец.
	local base = if #waitQueue == 0 then pickFreeBase() else nil
	if base then
		-- Без уведомления: клиент встречает базу большим баннером «ТВОЯ БАЗА — ЛАЗУРНАЯ!»
		-- (HudController), который влетает в плашку базы.
		assignBase(player, state, base)
	else
		player:SetAttribute("BaseIndex", 0)
		table.insert(waitQueue, player)
		serveQueue() -- если база уже освободилась, но ещё не роздана, раздадим по очереди
		if not state.Base then
			Notify.Send(player, "Все базы заняты — ждём свободную", "warning")
		end
	end

	spawnCharacter(player)
end

local function onPlayerRemoving(player: Player)
	local state = states[player]
	if not state then
		return
	end
	states[player] = nil

	local queueIndex = table.find(waitQueue, player)
	if queueIndex then
		table.remove(waitQueue, queueIndex)
	end

	setRespawnThread(state, nil)

	state.Trove:Clean()
	homeCooldown:Clear(player)
	releaseBase(player, state)
end

--------------------------------------------------------------------------------
-- Публичное API
--------------------------------------------------------------------------------

function BaseService:GetBase(player: Player): Base?
	local state = states[player]
	return state and state.Base
end

function BaseService:GetBases(): { Base }
	return bases
end

function BaseService:GetBaseFromInstance(instance: Instance): Base?
	local current: Instance? = instance
	while current do
		if current:IsA("Model") then
			local base = baseByModel[current]
			if base then
				return base
			end
		end
		current = current.Parent
	end
	return nil
end

-- Пересоздать персонажа игрока (появится на своей базе). Другие сервисы должны
-- пользоваться этим методом, а не вызывать LoadCharacterAsync напрямую.
function BaseService:RespawnPlayer(player: Player)
	task.spawn(spawnCharacter, player)
end

-- Телепортирует живого персонажа на площадку его базы.
function BaseService:TeleportHome(player: Player): boolean
	local base = self:GetBase(player)
	local character = player.Character
	if not base or not character or not character.Parent then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or not character:FindFirstChild("HumanoidRootPart") then
		return false
	end
	if humanoid.Sit then
		humanoid.Sit = false
	end
	character:PivotTo(self:GetSpawnCFrame(base))
	return true
end

--------------------------------------------------------------------------------
-- Жизненный цикл сервиса
--------------------------------------------------------------------------------

function BaseService:Init()
	-- Спауном управляем сами (см. spawnCharacter). В Place1.rbxl это тоже выключено.
	Players.CharacterAutoLoads = false

	local template = ServerStorage:FindFirstChild("BaseTemplate")
	assert(template and template:IsA("Model"), "[BaseService] нет ServerStorage.BaseTemplate (Model)")
	assert(template.PrimaryPart, "[BaseService] у BaseTemplate не задан PrimaryPart")

	local folder = Workspace:FindFirstChild("Bases") or Instance.new("Folder")
	folder.Name = "Bases"
	folder.Parent = Workspace

	for index, slot in getSlots() do
		local base = createBase(template, slot, index, folder)
		table.insert(bases, base)
		baseByModel[base.Model] = base
	end
	assert(
		#bases > 0,
		"[BaseService] не создано ни одной базы — проверь Workspace.Map.BaseSlots"
	)
	print(`[BaseService] создано баз: {#bases}`)
end

function BaseService:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	-- Игроки, которые успели зайти до запуска скрипта (бывает в Studio).
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Аргументы от клиента не нужны и игнорируются.
	Net.Event("RequestHome").OnServerEvent:Connect(function(player: Player)
		if not states[player] or not homeCooldown:TryUse(player) then
			return
		end
		if not self:TeleportHome(player) then
			Notify.Send(player, "Сейчас нельзя вернуться домой", "warning")
		end
	end)
end

return BaseService
