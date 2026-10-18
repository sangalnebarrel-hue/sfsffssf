--!strict
--[[
	MarketService — ларьки «ПРОДАТЬ РЫБУ» (Этап 3): рынок на острове и 4 ларька на мостах
	(EconomyConfig.SellPoints) — их кнопки и ставка продажи игрока по проверкам сервера.

	Что делает:
	  1. Start: для каждого ларька SellPoints (Attachment по Path; нет — один warn и дальше)
	     ProximityPrompt "SellPrompt": ActionText «Продать рыбу», ObjectText «Рыбный рынок · +50%» /
	     «Ларёк · +50%» (EconomyConfig.Prompt), HoldDuration 0.25, MaxActivationDistance 10,
	     RequiresLineOfSight false. PlayerAdded: атрибуты SellRatePct = HomeRatePct, SellPlace = "".
	  2. Sample(player) — зовёт TankService из своего цикла раз в секунду (не каждый кадр): позиция
	     HumanoidRootPart (FindFirstChild, без ожиданий); в Range ларька — dwell + 1 (тот же
	     ларёк), иначе 0. Скачок с прошлой проверки дальше WalkSpeed × dt × MarketJump.SpeedFactor
	     + MarketJump.Slack (телепорт) или новый персонаж (прошлой позиции нет) — «выдержка»
	     hold = MarketJump.Penalty: ставка ларька ждёт ещё столько чистых проверок (каждая
	     −1). Законные телепорты — «Домой», возрождение, вход — ставят игрока у его базы, а
	     оттуда до любого ларька идти дольше выдержки: живому игроку она не видна; «к ларьку
	     телепортом и сразу продать» — по ×1 ещё Penalty секунд. SellRatePct = MarketRatePct,
	     если dwell ≥ MarketDwell, hold = 0 и игрок всё ещё в Range, иначе HomeRatePct; атрибуты
	     SellRatePct / SellPlace — только при изменении.
	  3. RatePct(player) -> (ratePct, pointId?) — ставка по проверкам + живая проверка расстояния
	     до того же ларька; никогда не ждёт (TankService зовёт её в миг продажи).
	  4. Нажатие кнопки ларька — через лимит запросов игрока (Lib.TankRequests, общий с садком),
	     проверка расстояния сервером (не дальше MaxDistance + Slack). Кнопку держали у ларька —
	     это и есть «постоял у ларька»: если игрок в Range, выдержки нет и от прошлой проверки до
	     сих пор не было скачка (та же мерка, что в Sample; позиция проверки при этом не
	     меняется — частые нажатия не смягчают проверку скачков и не убавляют hold), dwell
	     засчитан сразу: SellRatePct = MarketRatePct ДО ответа — панель открывается уже с ценами
	     рынка, без ×1 на первые секунды. Скачок — hold = Penalty, по ×1. Потом TankEvent("Open",
	     { Place = Id ларька, RatePct = сейчас, Name }) — только открыть панель; цену в миг
	     продажи решает RatePct.
	Записи игроков — по самому Player (повторный вход — новый Player); соединения — только общие
	(PlayerAdded / PlayerRemoving, по одному Triggered на ларёк), на игрока — ни одного.

	Атрибуты Player: SellRatePct (100 | 150), SellPlace ("" | "Market" | "Kiosk1".."Kiosk4").

	API:
	  MarketService:Sample(player)                 -- TankService, раз в секунду
	  MarketService:RatePct(player) -> (number, string?)
	  MarketService._debugSizes()                  -- тесты: после выхода всех — нули
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local EconomyConfig = require(Shared.Config.EconomyConfig)
local Net = require(Shared.Net)
local TextUtil = require(Shared.TextUtil)
local TankRequests = require(ServerScriptService.Lib.TankRequests)

type Point = {
	Def: EconomyConfig.SellPoint,
	Attachment: Attachment,
	Prompt: ProximityPrompt,
}

type Record = {
	LastPos: Vector3?, -- позиция на прошлой проверке
	LastAt: number, -- os.clock() прошлой проверки
	Dwell: number, -- проверок подряд у ларька PointId
	Hold: number, -- столько чистых проверок ставка ларька ещё ждёт (скачок, новый персонаж)
	PointId: string?,
	RatePct: number, -- записано в атрибут SellRatePct
	Place: string, -- записано в атрибут SellPlace
}

local HOME = EconomyConfig.HomeRatePct
local MARKET = EconomyConfig.MarketRatePct
local PROMPT = EconomyConfig.Prompt
local JUMP = EconomyConfig.MarketJump
local DEFAULT_WALK_SPEED = 16

local MarketService = {}

local points: { Point } = {}
local pointById: { [string]: Point } = {}
local records: { [Player]: Record } = {}
local tankEvent: RemoteEvent? = nil

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function walkSpeed(player: Player): number
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if humanoid then humanoid.WalkSpeed else DEFAULT_WALK_SPEED
end

-- Скачок (телепорт): от прошлой проверки дальше, чем можно пройти за dt (с запасом).
local function jumped(player: Player, last: Vector3, position: Vector3, dt: number): boolean
	return (position - last).Magnitude > walkSpeed(player) * dt * JUMP.SpeedFactor + JUMP.Slack
end

local function inRange(point: Point, position: Vector3): boolean
	return (point.Attachment.WorldPosition - position).Magnitude <= point.Def.Range
end

-- Ближайший ларёк в его Range от position (или nil).
local function pointAt(position: Vector3): Point?
	local best: Point? = nil
	local bestDistance = math.huge
	for _, point in points do
		local distance = (point.Attachment.WorldPosition - position).Magnitude
		if distance <= point.Def.Range and distance < bestDistance then
			best, bestDistance = point, distance
		end
	end
	return best
end

local function newRecord(): Record
	return {
		LastPos = nil,
		LastAt = os.clock(),
		Dwell = 0,
		Hold = 0,
		PointId = nil,
		RatePct = HOME,
		Place = "",
	}
end

local function publish(player: Player, rec: Record, ratePct: number, place: string)
	if rec.RatePct ~= ratePct then
		rec.RatePct = ratePct
		player:SetAttribute("SellRatePct", ratePct)
	end
	if rec.Place ~= place then
		rec.Place = place
		player:SetAttribute("SellPlace", place)
	end
end

local function findAttachment(path: string): Attachment?
	local node: Instance? = Workspace
	for name in string.gmatch(path, "[^%.]+") do
		node = node and node:FindFirstChild(name)
	end
	return if node and node:IsA("Attachment") then node else nil
end

-- Кнопку ларька держали рядом с ним: dwell засчитан сразу (если не было скачка). Позиция
-- прошлой проверки не меняется: нажатия — не проверки.
local function arrive(player: Player, point: Point, root: BasePart)
	local rec = records[player]
	if not rec or rec.RatePct > HOME then
		return
	end
	local last = rec.LastPos
	if rec.Hold > 0 or not last then
		return -- (выдержка после скачка; нет прошлой проверки — нечем мерить скачок)
	end
	local position = root.Position
	if jumped(player, last, position, os.clock() - rec.LastAt) then
		rec.Hold = JUMP.Penalty
		rec.Dwell = 0
		return
	end
	if not inRange(point, position) then
		return
	end
	if rec.PointId ~= point.Def.Id then
		rec.PointId = point.Def.Id
		rec.Dwell = 0
	end
	rec.Dwell = math.max(rec.Dwell, EconomyConfig.MarketDwell)
	publish(player, rec, MARKET, point.Def.Id)
end

local function onTriggered(point: Point, player: Player)
	if not TankRequests.Take(player) then
		return
	end
	local root = rootOf(player)
	if not root or (point.Attachment.WorldPosition - root.Position).Magnitude > PROMPT.MaxDistance + PROMPT.Slack then
		return
	end
	arrive(player, point, root)
	local ratePct = MarketService:RatePct(player)
	local remote = tankEvent
	if remote and player.Parent == Players then
		remote:FireClient(player, "Open", { Place = point.Def.Id, RatePct = ratePct, Name = point.Def.Name })
	end
end

local function onPlayerAdded(player: Player)
	if records[player] or player.Parent ~= Players then
		return
	end
	records[player] = newRecord()
	player:SetAttribute("SellRatePct", HOME)
	player:SetAttribute("SellPlace", "")
end

local function onPlayerRemoving(player: Player)
	records[player] = nil
	TankRequests.Forget(player)
end

--------------------------------------------------------------------------------
-- Публичное API
--------------------------------------------------------------------------------

function MarketService:Sample(player: Player)
	local rec = records[player]
	if not rec then
		return
	end
	local now = os.clock()
	local dt = now - rec.LastAt
	rec.LastAt = now
	local root = rootOf(player)
	if not root then
		rec.LastPos = nil
		rec.Dwell = 0
		rec.PointId = nil
		publish(player, rec, HOME, "")
		return
	end
	local position = root.Position
	local last = rec.LastPos
	rec.LastPos = position
	if not last or jumped(player, last, position, dt) then
		rec.Hold = JUMP.Penalty -- скачок (телепорт) или новый персонаж: выдержка
	elseif rec.Hold > 0 then
		rec.Hold -= 1
	end
	local point = pointAt(position)
	if point then
		if point.Def.Id ~= rec.PointId then
			rec.Dwell = 0
		end
		rec.PointId = point.Def.Id
		rec.Dwell += 1
	else
		rec.PointId = nil
		rec.Dwell = 0
	end
	if point and rec.Dwell >= EconomyConfig.MarketDwell and rec.Hold == 0 then
		publish(player, rec, MARKET, point.Def.Id)
	else
		publish(player, rec, HOME, "")
	end
end

function MarketService:RatePct(player: Player): (number, string?)
	local rec = records[player]
	if not rec or rec.RatePct <= HOME or not rec.PointId then
		return HOME, nil
	end
	local point = pointById[rec.PointId]
	local root = rootOf(player)
	if not point or not root or not inRange(point, root.Position) then
		return HOME, nil -- ушёл от ларька после проверки
	end
	return rec.RatePct, point.Def.Id
end

function MarketService._debugSizes(): { [string]: number }
	local n = 0
	for _ in records do
		n += 1
	end
	return { Records = n }
end

--------------------------------------------------------------------------------
-- Жизненный цикл сервиса
--------------------------------------------------------------------------------

function MarketService:Start()
	tankEvent = Net.Event("TankEvent")
	local bonus = MARKET - HOME
	for _, def in EconomyConfig.SellPoints do
		local attachment = findAttachment(def.Path)
		if not attachment then
			warn(`[MarketService] нет ларька {def.Id}: Workspace.{def.Path} — пропускаю`)
			continue
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "SellPrompt"
		prompt.ActionText = PROMPT.Action
		prompt.ObjectText = TextUtil.fill(PROMPT.Object, { name = def.Name, bonus = tostring(bonus) })
		prompt.HoldDuration = PROMPT.HoldDuration
		prompt.MaxActivationDistance = PROMPT.MaxDistance
		prompt.RequiresLineOfSight = false
		prompt.Parent = attachment
		local point: Point = { Def = def, Attachment = attachment, Prompt = prompt }
		table.insert(points, point)
		pointById[def.Id] = point
		prompt.Triggered:Connect(function(player: Player)
			onTriggered(point, player)
		end)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return MarketService
