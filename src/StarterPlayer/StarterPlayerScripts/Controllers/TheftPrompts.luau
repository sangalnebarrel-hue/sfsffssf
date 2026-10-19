--!strict
--[[
	TheftPrompts — фильтр кнопок «Украсть» на ЭТОМ клиенте (Этап 4, docs/stage4_design.md §5.1;
	помощник TheftController — модуль, не контроллер: его нет в ClientMain.ORDER).

	Кнопки "StealPrompt" (по одной на витрину каждой базы, Tank.Slots.Slot_K.Pedestal.
	PromptAttachment) создаёт сервер (StealService) и пишет им Enabled, ObjectText и HoldDuration.
	Прячет кнопку только клиент — МЕСТНЫМ MaxActivationDistance = 0 (показать — снова
	StealConfig.Prompt.MaxDistance): это свойство сервер после создания больше не пишет, так что
	ни одна его запись не вернёт спрятанную кнопку (в Roblox запись сервера перезаписывает
	местное значение того же свойства — BE-14; в RbxSim так же: S1 / S2). Сервер всё равно
	проверяет всё сам (Shared/TheftChecks).

	Прячет (строки Shared/TheftChecks с Client = true, через StealRules.CanStealView — фильтр и
	отказ сервера не расходятся):
	  • всё на своей базе и всё, пока своей базы нет (или её садок не подключён);
	  • всё, пока крадёшь (Stealing) или ждёшь (StealCooldownUntil — серверное время);
	  • всю базу под защитой (ProtectUntil / ProtectKind) или с кражей (Thief);
	  • витрину без рыбы, с кражей (StealPhase), «в пути» (Escrow) и свежий улов (FreshUntil);
	  • всю базу, если у хозяина меньше Limits.MinFishToRob рыб (Tank.Count) или он намного
	    слабее (доходы — атрибуты Income игроков);
	  • рыбу, которой нет места в своём садке: свободной витрины нет, а она не сильнее своей
	    слабейшей не краденой и не «в пути» (TankRules.ChooseReplacement, как TankService:
	    PreviewAdd).
	Никогда — кнопку, которую этот игрок сейчас держит (SetHeld): кнопка, ушедшая из радиуса,
	сама гасит удержание; её гасит только сервер (Cancel / Denied → InputHoldEnd в
	TheftController). Когда удержание кончилось и рыба на голове (Stealing = "carry"), прячется и
	она.

	Когда пересчитывается: на смену нужных атрибутов (своего игрока, витрин, моделей баз и
	садков, доходов игроков) — один раз в конце кадра (task.defer), и одним task.delay к
	ближайшему сроку (конец ожидания, защиты базы, свежего улова). Ни одного покадрового
	соединения. Соединения — на сессию (базы и витрины живут всю игру), у ушедшего игрока —
	снимаются.

	API:
	  TheftPrompts.Start()                     -- один раз (TheftController:Start)
	  TheftPrompts.SetHeld(prompt?)            -- кнопка, которую держит этот игрок (nil — никакая)
	  TheftPrompts.Refresh()                   -- пересчитать сейчас
	  TheftPrompts.PromptAt(baseIndex, slot) -> ProximityPrompt?
	  TheftPrompts.IsSteal(prompt) -> boolean   -- это кнопка кражи
	  TheftPrompts.BaseReason(base) -> (reason?, left?)   -- почему на этой базе ничего нельзя
	  TheftPrompts.FishReason(base) -> (reason?, left?)   -- почему ни одна её рыба (когда кнопок нет)
	  TheftPrompts.Shown(base) -> number       -- сколько её кнопок сейчас видно
	  TheftPrompts.Stats() -> { Prompts, Shown, Connections }   -- тесты
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local StealConfig = require(Config:WaitForChild("StealConfig"))
local StealRules = require(Shared:WaitForChild("StealRules"))
local TankRules = require(Shared:WaitForChild("TankRules"))
local TheftChecks = require(Shared:WaitForChild("TheftChecks"))

local player = Players.LocalPlayer

local PROMPT_NAME = "StealPrompt"
local SHOW = StealConfig.Prompt.MaxDistance
local EXPIRY_SLACK = 0.05 -- пересчёт чуть позже срока (атрибуты времени — с добавкой AttrTime)

-- Атрибуты, от которых зависит фильтр (остальные изменения — мимо).
local SLOT_FIELDS = {
	State = true,
	FishUid = true,
	Income = true,
	Value = true,
	GrowFrom = true,
	StealPhase = true,
	Escrow = true,
	FreshUntil = true,
}
local BASE_FIELDS = { ProtectUntil = true, ProtectKind = true, Thief = true, OwnerUserId = true }
local OWN_FIELDS = { BaseIndex = true, Stealing = true, StealCooldownUntil = true, Income = true, TankSlots = true }

type Info = {
	prompt: ProximityPrompt,
	base: Model,
	slot: Instance,
	index: number,
}

-- Свой садок для «ляжет ли добыча» (TankService:PreviewAdd): кандидаты замены и свободная витрина.
type Own = { candidates: { TankRules.Candidate }, free: boolean }

local TheftPrompts = {}

local infos: { [ProximityPrompt]: Info } = {}
local byBase: { [Model]: { Info } } = {}
local shownBy: { [Model]: number } = {}
local held: ProximityPrompt? = nil
local dirty = false
local expiryToken = 0
local started = false
local connections: { RBXScriptConnection } = {}
local playerConnections: { [Player]: RBXScriptConnection } = {}

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

-- Атрибут-число (конечное) или nil.
local function num(x: any): number?
	return if finite(x) then x :: number else nil
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function basesFolder(): Instance?
	return Workspace:FindFirstChild("Bases")
end

local function baseByIndex(index: any): Model?
	local folder = basesFolder()
	if not folder or type(index) ~= "number" or index <= 0 then
		return nil
	end
	local base = folder:FindFirstChild(`Base_{index}`)
	return if base and base:IsA("Model") then base else nil
end

local function ownBase(): Model?
	return baseByIndex(player:GetAttribute("BaseIndex"))
end

local function ownerOf(base: Model): Player?
	local id = base:GetAttribute("OwnerUserId")
	if type(id) ~= "number" or id <= 0 then
		return nil
	end
	return Players:GetPlayerByUserId(id)
end

-- Десятые $/с из атрибута Income ($/с с десятыми: доход садка, Income10Sum / 10).
local function tenths(income: any): number?
	local value = num(income)
	return if value then math.round(value * 10) else nil
end

local function tankOf(base: Model): Instance?
	return base:FindFirstChild("Tank")
end

-- Свой садок: живые рыбы как кандидаты замены (краденую у меня и «в пути» — Locked) и есть ли
-- свободная (открытая, пустая) витрина.
local function ownTank(base: Model?, now: number): Own
	local own: Own = { candidates = {}, free = false }
	local tank = base and tankOf(base)
	local slots = tank and tank:FindFirstChild("Slots")
	if not slots then
		return own
	end
	for _, slot in slots:GetChildren() do
		local state = slot:GetAttribute("State")
		if state == "empty" then
			own.free = true
		elseif state == "fish" then
			local growFrom = num(slot:GetAttribute("GrowFrom"))
			table.insert(own.candidates, {
				Uid = tostring(slot:GetAttribute("FishUid")),
				Income10 = tenths(slot:GetAttribute("Income")) or 0,
				Value = num(slot:GetAttribute("Value")) or 0,
				Age = if growFrom then math.max(0, now - growFrom) else 0,
				Locked = slot:GetAttribute("Escrow") == true or slot:GetAttribute("StealPhase") ~= nil,
			})
		end
	end
	return own
end

-- Поля базы и вора (без витрины): то, что клиент знает (nil — не знает: строку пропускает).
local function baseView(base: Model, now: number, own: Model?): TheftChecks.View
	local tank = tankOf(base)
	local owner = ownerOf(base)
	local protectUntil = num(base:GetAttribute("ProtectUntil"))
	local kind = base:GetAttribute("ProtectKind")
	local cooldown = num(player:GetAttribute("StealCooldownUntil"))
	local count = if tank then num(tank:GetAttribute("Count")) else nil
	local ownTankModel = own and tankOf(own)
	return {
		Own = own ~= nil and base == own,
		ThiefMounted = own ~= nil and ownTankModel ~= nil and ownTankModel:GetAttribute("Count") ~= nil,
		Stealing = player:GetAttribute("Stealing") ~= nil,
		CooldownLeft = if cooldown then cooldown - now else 0,
		ProtectLeft = if protectUntil then protectUntil - now else 0,
		ProtectKind = if type(kind) == "string" then kind else nil,
		BaseTheft = base:GetAttribute("Thief") ~= nil,
		VictimActive = count,
		ThiefIncome10 = tenths(player:GetAttribute("Income")),
		VictimIncome10 = if owner then tenths(owner:GetAttribute("Income")) else nil,
		Now = now,
	}
end

-- Поля витрины поверх полей базы.
local function slotView(view: TheftChecks.View, slot: Instance, now: number, own: Own): TheftChecks.View
	local v = table.clone(view)
	local state = slot:GetAttribute("State")
	local fresh = num(slot:GetAttribute("FreshUntil"))
	v.FishMissing = state ~= "fish"
	v.FishTaken = slot:GetAttribute("StealPhase") ~= nil or slot:GetAttribute("Escrow") == true
	v.FreshLeft = if fresh then fresh - now else 0
	if state == "fish" then
		local income10 = tenths(slot:GetAttribute("Income")) or 0
		v.Placeable = StealRules.CanPlace(own.candidates, own.free, income10) ~= nil
	end
	return v
end

local function apply(prompt: ProximityPrompt, show: boolean)
	local want = if show then SHOW else 0
	if prompt.MaxActivationDistance ~= want then
		prompt.MaxActivationDistance = want
	end
end

-- Ближайший будущий срок (ожидание, защита баз, свежий улов) — пересчёт к нему одним task.delay.
local function scheduleExpiry(now: number)
	local soonest = math.huge
	local cooldown = num(player:GetAttribute("StealCooldownUntil"))
	if cooldown and cooldown > now then
		soonest = cooldown
	end
	for base, list in byBase do
		local protect = num(base:GetAttribute("ProtectUntil"))
		if protect and protect > now then
			soonest = math.min(soonest, protect)
		end
		for _, info in list do
			local fresh = num(info.slot:GetAttribute("FreshUntil"))
			if fresh and fresh > now then
				soonest = math.min(soonest, fresh)
			end
		end
	end
	expiryToken += 1
	if soonest == math.huge then
		return
	end
	local token = expiryToken
	task.delay(soonest - now + EXPIRY_SLACK, function()
		if token == expiryToken then
			TheftPrompts.Refresh()
		end
	end)
end

function TheftPrompts.Refresh()
	dirty = false
	local now = serverNow()
	local own = ownBase()
	local tank = ownTank(own, now)
	local carrying = player:GetAttribute("Stealing") == "carry"
	for base, list in byBase do
		local view = baseView(base, now, own)
		local shown = 0
		for _, info in list do
			local reason = StealRules.CanStealView(slotView(view, info.slot, now, tank))
			local show = reason == nil
			if info.prompt == held and not carrying then
				show = true -- (держит сам: гасит только сервер)
			end
			apply(info.prompt, show)
			if show then
				shown += 1
			end
		end
		shownBy[base] = shown
	end
	scheduleExpiry(now)
end

local function markDirty()
	if dirty or not started then
		return
	end
	dirty = true
	task.defer(function()
		if dirty then
			TheftPrompts.Refresh()
		end
	end)
end

-- Кнопка кражи: base и номер витрины по пути Base_N.Tank.Slots.Slot_K.Pedestal.PromptAttachment.
local function register(prompt: ProximityPrompt)
	if infos[prompt] then
		return
	end
	local attachment = prompt.Parent
	local pedestal = attachment and attachment.Parent
	local slot = pedestal and pedestal.Parent
	local slots = slot and slot.Parent
	local tank = slots and slots.Parent
	local base = tank and tank.Parent
	if not (slot and tank and base and base:IsA("Model")) then
		return
	end
	local index = tonumber(string.match(slot.Name, "^Slot_(%d+)$"))
	if not index then
		return
	end
	local info: Info = { prompt = prompt, base = base, slot = slot, index = index }
	infos[prompt] = info
	local list = byBase[base]
	if not list then
		list = {}
		byBase[base] = list
		table.insert(
			connections,
			base.AttributeChanged:Connect(function(name: string)
				if BASE_FIELDS[name] then
					markDirty()
				end
			end)
		)
		table.insert(
			connections,
			tank.AttributeChanged:Connect(function(name: string)
				if name == "Count" then
					markDirty()
				end
			end)
		)
	end
	table.insert(list, info)
	table.insert(
		connections,
		slot.AttributeChanged:Connect(function(name: string)
			if SLOT_FIELDS[name] then
				markDirty()
			end
		end)
	)
	apply(prompt, false) -- (пока не посчитано — спрятана: лишний кадр «Украсть» на своей базе хуже)
	markDirty()
end

local function watchPlayer(other: Player)
	if other == player or playerConnections[other] then
		return
	end
	playerConnections[other] = other.AttributeChanged:Connect(function(name: string)
		if name == "Income" then
			markDirty()
		end
	end)
end

function TheftPrompts.Start()
	if started then
		return
	end
	started = true
	local folder = basesFolder() or Workspace:WaitForChild("Bases", 10)
	if folder then
		for _, item in folder:GetDescendants() do
			if item:IsA("ProximityPrompt") and item.Name == PROMPT_NAME then
				register(item)
			end
		end
		table.insert(
			connections,
			folder.DescendantAdded:Connect(function(item: Instance)
				if item:IsA("ProximityPrompt") and item.Name == PROMPT_NAME then
					register(item)
				end
			end)
		)
	end
	table.insert(
		connections,
		player.AttributeChanged:Connect(function(name: string)
			if OWN_FIELDS[name] then
				markDirty()
			end
		end)
	)
	for _, other in Players:GetPlayers() do
		watchPlayer(other)
	end
	table.insert(connections, Players.PlayerAdded:Connect(watchPlayer))
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(other: Player)
			local connection = playerConnections[other]
			playerConnections[other] = nil
			if connection then
				connection:Disconnect()
			end
			markDirty()
		end)
	)
	TheftPrompts.Refresh()
end

function TheftPrompts.SetHeld(prompt: ProximityPrompt?)
	if held == prompt then
		return
	end
	held = prompt
	if prompt and infos[prompt] then
		apply(prompt, true)
	end
	markDirty()
end

function TheftPrompts.IsSteal(prompt: Instance?): boolean
	return prompt ~= nil and prompt:IsA("ProximityPrompt") and infos[prompt :: ProximityPrompt] ~= nil
end

function TheftPrompts.PromptAt(baseIndex: any, slot: any): ProximityPrompt?
	local base = baseByIndex(baseIndex)
	local list = base and byBase[base]
	if not list then
		return nil
	end
	for _, info in list do
		if info.index == slot then
			return info.prompt
		end
	end
	return nil
end

-- Почему на базе ничего нельзя (строки базы и вора; nil — можно, дальше решают витрины).
function TheftPrompts.BaseReason(base: Model): (string?, number?)
	return StealRules.CanStealView(baseView(base, serverNow(), ownBase()))
end

-- Почему ни одна рыба базы (когда её кнопок не видно, а база в порядке): из причин витрин с
-- рыбой — та, что кончится раньше («свежий улов»), иначе первая по порядку проверок.
function TheftPrompts.FishReason(base: Model): (string?, number?)
	local list = byBase[base]
	if not list then
		return nil, nil
	end
	local now = serverNow()
	local own = ownBase()
	local view = baseView(base, now, own)
	local tank = ownTank(own, now)
	local best: string?, bestLeft: number? = nil, nil
	for _, info in list do
		if info.slot:GetAttribute("State") == "fish" then
			local reason, left = StealRules.CanStealView(slotView(view, info.slot, now, tank))
			if reason and reason ~= "missing" then
				if best == nil or (left and (bestLeft == nil or left < bestLeft)) then
					best, bestLeft = reason, left
				end
			end
		end
	end
	return best, bestLeft
end

function TheftPrompts.Shown(base: Model): number
	return shownBy[base] or 0
end

function TheftPrompts.Stats(): { [string]: number }
	local prompts, shown = 0, 0
	for prompt in infos do
		prompts += 1
		if prompt.MaxActivationDistance > 0 then
			shown += 1
		end
	end
	local players = 0
	for _ in playerConnections do
		players += 1
	end
	return { Prompts = prompts, Shown = shown, Connections = #connections + players }
end

return TheftPrompts
