--!strict
--[[
	TankService — садок игрока (Этап 3): рыбы в витринах двора базы (Tank.Slots.Slot_1..12),
	открытые витрины, «спящие» рыбы, правило полного садка, продажа, общий цикл дохода раз в
	секунду, атрибуты витрин и садка, таблички и подсветка витрин, кнопка у большого аквариума,
	remote'ы садка и хук сохранения. Правила и вид сумм — TankRules, числа — TankConfig /
	EconomyConfig, данные — DataService (поля Tank, TankSlots, NextUid, Stats.Sold — его).
	Подробно — scratchpad design.md, §3.3, §4.3, §4.5, §4.6, §5.2.

	Что делает:
	  1. Init: у каждой базы ссылки витрин Slot_1..12 — Pedestal, Display, Display.FishPoint,
	     Pedestal.LabelGui.Label, LightBar и его SurfaceLight (нет — громкая ошибка), и вид
	     шаблона (его возвращают пустым витринам); у всех витрин State = "empty"; кнопка
	     ProximityPrompt "TankPrompt" на Tank.Glass.PromptAttachment (TankConfig.Prompt: «Открыть» /
	     «Садок», HoldDuration 0, MaxActivationDistance 10, RequiresLineOfSight false, Enabled
	     false); хук DataService:OnSerialize (обновить возраст рыб на базе; Этап 4 — какие uid не
	     сохранять, в Этапе 3 — никаких).
	  2. DataService.Loaded → записи рыб: Rarity, Value, Income10 — из FishingRules.Price; рыба
	     «спит» (Dormant), если вид незнаком или у неё нет своей витрины (PlayerData.Layout):
	     не видна, без дохода, не продаётся, не заменяется, сохраняется как есть. Атрибуты игрока
	     TankCount / TankSlots.
	  3. «Подключение» садка к базе — когда у игрока есть И данные, И база (что второе; и
	     BaseService.BaseAssigned): GrowFrom = AttrTime(сейчас − Age) каждой активной рыбы,
	     витрины 1..12 (атрибуты, таблички, подсветка) с Event "<n>|mount|", атрибуты садка и
	     игрока, доход, кнопка включена. Отключение (BaseReleased, выход): Age каждой рыбы замирает,
	     все витрины — "empty" / «Пусто» / вид шаблона, поля рыбы — nil, Event "<n>|mount|" (тихо
	     перечитать), атрибуты садка сняты, доход игрока 0, кнопка выключена.
	  4. Улов: FishingService.SetCatchSink(sink) (только если это функция — заглушки сервисов в
	     тестах); sink(player, fish) -> TankResult? — nil без CanWrite или без базы (это лишь
	     гонка выхода / закрытия: заброс до загрузки не принимается), иначе AddFish(player, fish,
	     "catch"). Синхронно, без ожиданий.
	  5. AddFish(player, fish, reason) — за DataService:CanWrite. Сначала посчитать: цену и
	     доход заново (FishingRules.Price — клиенту и улову не верим), решение полного садка, цены
	     продажи; потом менять: data.Tank (Uid = PlayerData.NewUid) → записи →
	     EconomyService:AddMoney(…, "autosell") при "replaced" / "sold" → Stats.Sold + 1 → атрибуты
	     витрины (Event последним) → доход → атрибуты → FishRemoved / FishAdded. Полный садок:
	       есть свободная открытая витрина → в самую младшую → "stored" (Event "<n>|in|<FishId>");
	       иначе слабейшая активная (не Locked, не Dormant) — TankRules.ChooseReplacement: доход
	       новой больше → слабейшую продать по SellPrice(…, возраст сейчас, HomeRatePct), новая на
	       её место → "replaced" (Event "<n>|swap|<цена>"); иначе новую продать сразу по
	       SellPrice(Value, 0, HomeRatePct) → "sold" (витрины не меняются, номер не тратится).
	     Возвращает TankResult { Result, Slot?, Uid?, Count, Slots, Replaced?, Price?, First? }
	     (First — улов и Stats.Caught == 1: первое уведомление и «!»). Price — ВСЕГДА монеты, которые
	     зачислил этот AddFish (клиент празднует именно их): "replaced" — Price == Replaced.Price
	     (цена проданной слабейшей), "sold" — цена новой рыбы, "stored" — nil. Рыба не из улова
	     (Этап 4: кража) — ещё и TankEvent("Stored", результат + { Fish }). Без базы (Этап 4: вор в
	     очереди) — только данные, витрины покажет подключение.
	  6. Продажа TankSell(uid) — проверки по порядку из шапки RemoteNames (uid, лимит запросов
	     Lib.TankRequests — из него же каждый ответ, CanWrite, база, своя активная рыба, не
	     Locked, конечная цена), потом без ожиданий: возраст сейчас и цена
	     TankRules.SellPrice(Value, ageNow, MarketService:RatePct(player)), убрать из data.Tank
	     (плотно) и записей, AddMoney(…, "sell"), Stats.Sold + 1, витрина ("empty", поля nil, Event
	     "<n>|sold|<цена>"), доход, TankEvent("Sold", { Items, Amount, RatePct, Place }),
	     FishRemoved.
	  7. Кнопка "TankPrompt" (Triggered) — через тот же лимит запросов; только хозяину базы и после
	     проверки расстояния сервером (≤ MaxDistance + Slack): TankEvent("Open", { Place = "Tank",
	     RatePct = атрибут SellRatePct, Name = «Садок» }).
	  8. Цикл дохода — ОДИН task.spawn на сервер: dt = task.wait(IncomeTick), накопитель с
	     фиксированным шагом (acc += dt; n = floor(acc / IncomeTick); acc −= n · IncomeTick;
	     n = min(n, MaxCatchUp)); по записям ЭТОГО сервиса (не Players:GetPlayers), только
	     подключённым и с CanWrite: carry10 += n · Income10Sum, целые монеты — AddMoney(…, "income"),
	     остаток (десятые) копится; возраст рыб для сохранения; MarketService:Sample(player). Шаг
	     игрока — в xpcall (warn не чаще раза в WARN_EVERY с), сам цикл — вне pcall: одна плохая
	     запись не останавливает всех. Ничего не ждёт (HumanoidRootPart — FindFirstChild).
	  9. Возраст: ageNow = clamp(GetServerTimeNow() − GrowFrom, 0, Time) — та же формула и те же
	     часы, что у клиента (TankRules.AgeAt; GrowFrom записи = атрибут витрины); продажа — по
	     ageNow в её миг; без базы (очередь) — ни дохода, ни роста. Income10Sum пересчитывается
	     только при изменении садка; атрибуты Income (игрок и садок) и «Доход/с» — при изменении,
	     не каждый тик.
	Записи игроков — по самому Player (повторный вход — новый Player) с проверкой «это всё ещё
	она»; соединений на игрока нет (одно Triggered на базу, общие события сервисов), всё на игрока —
	записи этого модуля, удаляются при выходе; без бесконечных списков (DataService, «Правила»).

	Вид витрины на сервере (при изменении): "empty" / свободная база — табличка «Пусто», LightBar
	как в шаблоне (AquaGlow, Neon, свет есть), стекло как в шаблоне (0.66); "fish" — табличка с
	именем рыбы, TextColor3 = цвет редкости (FishConfig), LightBar.Color = цвет редкости
	(UIConfig.Rarity[r].Bottom; мифическая — UIConfig.Rainbow[6]), свет есть, стекло
	Display.Transparency = TankConfig.Display.GlassOccupied; "locked" — «🔒 Закрыто», LightBar
	SmoothPlastic цвета Slate.Bottom, SurfaceLight выключен. Новых деталей на сервере нет.

	Атрибуты (RemoteNames, «Состояние садка и денег»): Player — TankCount, TankSlots (и Income —
	через EconomyService:SetIncome); Base_N.Tank — Count, Slots, Income; витрины — State, FishUid,
	FishId, Rarity, Mutation, Kg, Value, Income, GrowFrom (TankRules.AttrTime), Event
	("<n>|in|<FishId>", "<n>|mount|" — подключение и отключение садка, тихо, "<n>|sold|<цена>",
	"<n>|swap|<цена>", Этап 4 "<n>|stolen|"; поля рыбы → State → Event последним; пишутся только
	изменившиеся; n растёт у базы всё время работы сервера).
	Remote'ы: TankSell (клиент → сервер), TankEvent (сервер → клиент) — протокол в RemoteNames.

	Этап 4 (кража) — уже есть: RemoveFish(owner, uid, reason) и AddFish(thief, fish, "stolen")
	(то же правило полного садка; оба nil без CanWrite своего игрока), сигналы FishAdded /
	FishRemoved, Event "stolen" одним событием (RemoveFish с reason "stolen"), SetLocked(owner,
	uid, bool) (продажа — Denied "locked", рыба не заменяется), Pedestal.PromptAttachment свободна
	под кнопки кражи. Порядок кражи (никогда не дюп; худшее — одна потерянная рыба):
	1) RemoveFish(жертва, uid) → seqV = DataService:SaveSoon(жертва); 2) AddFish(вор, рыба,
	"stolen") — новый Uid из счётчика вора, Origin = "<UserId жертвы>:<uid>", в записи Escrow =
	{ жертва, seqV }: пока так — не продаётся, хук OnSerialize её не сохраняет; 3) когда
	Committed(жертва) ≥ seqV — Escrow снимается, SaveSoon(вор); 4) запись жертвы так и не легла
	(замок потерян) — рыба «в пути» пропадает, когда вор уходит. Две рыбы с одним Origin в садке —
	оставить одну.
	Этап 5 (магазин): SetSlots(player, n) — открывает следующие витрины (только больше, до любых
	n ≥ текущего; в игре — не больше MaxSlots: атрибуты, таблички) и будит «спящих» знакомых рыб
	в новых витринах.

	API:
	  TankService:AddFish(player, fish: FishData, reason) -> TankResult?
	  TankService:RemoveFish(owner, uid, reason) -> PlayerData.Fish?
	  TankService:SetLocked(owner, uid, locked) -> boolean
	  TankService:SetSlots(player, n) -> boolean
	  TankService.FishAdded, TankService.FishRemoved   -- Signal (player, fish, reason)
	  TankService._debugSizes()                        -- тесты: после выхода всех — нули
	  TankService._runtimeFor(player)                  -- тесты: запись игрока (Ticks — тиков дохода)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local EconomyConfig = require(Shared.Config.EconomyConfig)
local TankConfig = require(Shared.Config.TankConfig)
local UIConfig = require(Shared.Config.UIConfig)
local FishingRules = require(Shared.FishingRules)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local TankRules = require(Shared.TankRules)
local PlayerData = require(ServerScriptService.Lib.PlayerData)
local TankRequests = require(ServerScriptService.Lib.TankRequests)
local BaseService = require(ServerScriptService.Services.BaseService)
local DataService = require(ServerScriptService.Services.DataService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local FishingService = require(ServerScriptService.Services.FishingService)
local MarketService = require(ServerScriptService.Services.MarketService)

type FishData = FishingRules.FishData
type Base = BaseService.Base

-- Что продано при замене (TankResult.Replaced, TankEvent "Sold" Items).
export type SoldFish = {
	Uid: string,
	Id: string,
	Rarity: string,
	Mutation: string?,
	Price: number,
}

-- Что стало с рыбой (FishingState "Caught" Tank, TankEvent "Stored").
export type TankResult = {
	Result: "stored" | "replaced" | "sold",
	Slot: number?,
	Uid: string?,
	Count: number,
	Slots: number,
	Replaced: SoldFish?,
	-- монеты, зачисленные этим AddFish: "replaced" — == Replaced.Price, "sold" — цена новой, "stored" — nil
	Price: number?,
	First: boolean?,
}

-- Рыба садка в игре (сама запись — Rec, живая строка data.Tank).
type FishRt = {
	Rec: PlayerData.Fish,
	Uid: string,
	Rarity: string,
	Mutation: string?, -- знакомая мутация (незнакомая — как без мутации)
	Value: number, -- цена ×1
	Income10: number, -- доход, десятые в секунду
	GrowFrom: number, -- серверное время «в садке с» (атрибут витрины), пока садок подключён
	Locked: boolean, -- (Этап 4) её сейчас крадут
	Dormant: boolean,
}

type Runtime = {
	Player: Player,
	Data: PlayerData.Data,
	Fish: { [string]: FishRt }, -- все рыбы садка по Uid (и спящие)
	BySlot: { [number]: FishRt }, -- активные по витрине
	Base: Base?,
	Mounted: boolean,
	Income10Sum: number,
	Carry10: number, -- десятые монеты, ещё не зачисленные
	Ticks: number, -- тиков дохода зачислено (тесты)
}

-- Вид витрины в шаблоне (его получает пустая витрина).
type SlotLook = {
	LabelText: string,
	LabelColor: Color3,
	BarColor: Color3,
	BarMaterial: Enum.Material,
	LightEnabled: boolean,
	DisplayTransparency: number,
}

type SlotRefs = {
	Index: number,
	Model: Model,
	Display: BasePart,
	Label: TextLabel,
	LightBar: BasePart,
	Light: SurfaceLight,
	Template: SlotLook,
	Attrs: { [string]: any }, -- что уже записано в атрибуты (пишем только изменившееся)
	Look: string, -- что уже показано на табличке и подсветке
}

type BaseRefs = {
	Base: Base,
	Slots: { SlotRefs },
	Prompt: ProximityPrompt,
	PromptAttachment: Attachment,
	Serial: number, -- n событий витрин этой базы (растёт всё время работы сервера)
	Owner: Runtime?, -- чей садок подключён
	TankAttrs: { [string]: any },
}

local GROWTH_TIME = TankConfig.Growth.Time
local HOME = EconomyConfig.HomeRatePct
local TEXTS = TankConfig.Texts
local PROMPT = TankConfig.Prompt
local FISH_FIELDS = { "FishUid", "FishId", "Rarity", "Mutation", "Kg", "Value", "Income", "GrowFrom" }
local WARN_EVERY = 30 -- секунд между предупреждениями цикла дохода

local TankService = {
	FishAdded = Signal.new(), -- (player, fish, reason)
	FishRemoved = Signal.new(), -- (player, fish, reason)
}

local runtimes: { [Player]: Runtime } = {}
local baseRefs: { [Base]: BaseRefs } = {}
local tankEvent: RemoteEvent? = nil
local lastLoopWarn = -math.huge

--------------------------------------------------------------------------------
-- Помощники
--------------------------------------------------------------------------------

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

-- Обработчик xpcall: текст ошибки с трассировкой.
local function trace(err: any): string
	return debug.traceback(tostring(err), 2)
end

-- Цена продажи годится: целое, конечное, ≥ 1.
local function goodPrice(price: number): boolean
	return finite(price) and price >= 1 and price % 1 == 0
end

local function send(player: Player, kind: string, data: { [string]: any })
	local remote = tankEvent
	if remote and player.Parent == Players then
		remote:FireClient(player, kind, data)
	end
end

local function deny(player: Player, reason: string)
	send(player, "Denied", { Reason = reason, Text = TEXTS.Denied[reason] or "" })
end

local function knownMutation(mutation: any): string?
	return if type(mutation) == "string" and FishingRules.GetMutation(mutation) then mutation else nil
end

-- Возраст рыбы сейчас: у подключённого садка — по GrowFrom, иначе замерший Age.
local function ageOf(rt: Runtime, fish: FishRt, now: number): number
	if rt.Mounted then
		return TankRules.AgeAt(fish.GrowFrom, now)
	end
	return math.clamp(fish.Rec.Age, 0, GROWTH_TIME)
end

-- Рыба в игре по её записи данных (вид знаком: Price только для знакомых Id).
local function activeFish(rec: PlayerData.Fish): FishRt
	local def = FishingRules.GetFish(rec.Id) :: any
	local mutation = knownMutation(rec.Mutation)
	local value, income = FishingRules.Price(rec.Id, rec.Kg, mutation)
	return {
		Rec = rec,
		Uid = rec.Uid,
		Rarity = def.Rarity,
		Mutation = mutation,
		Value = value,
		Income10 = TankRules.Income10(income),
		GrowFrom = 0,
		Locked = false,
		Dormant = false,
	}
end

local function soldFish(fish: FishRt, price: number): SoldFish
	return { Uid = fish.Uid, Id = fish.Rec.Id, Rarity = fish.Rarity, Mutation = fish.Mutation, Price = price }
end

local function activeCount(rt: Runtime): number
	local n = 0
	for _ in rt.BySlot do
		n += 1
	end
	return n
end

-- Убрать строку из data.Tank (плотный массив).
local function removeEntry(data: PlayerData.Data, entry: PlayerData.Fish)
	local index = table.find(data.Tank, entry)
	if index then
		table.remove(data.Tank, index)
	end
end

--------------------------------------------------------------------------------
-- Витрины
--------------------------------------------------------------------------------

local function setAttr(slot: SlotRefs, name: string, value: any)
	if slot.Attrs[name] ~= value then
		slot.Attrs[name] = value
		slot.Model:SetAttribute(name, value)
	end
end

local function setTankAttr(refs: BaseRefs, name: string, value: any)
	if refs.TankAttrs[name] ~= value then
		refs.TankAttrs[name] = value
		refs.Base.Tank:SetAttribute(name, value)
	end
end

-- Event — ПОСЛЕДНИМ (после полей рыбы и State); n растёт у базы всегда.
local function event(refs: BaseRefs, slot: SlotRefs, kind: string, detail: string)
	refs.Serial += 1
	slot.Model:SetAttribute("Event", `{refs.Serial}|{kind}|{detail}`)
end

local function look(slot: SlotRefs, key: string, apply: () -> ())
	if slot.Look ~= key then
		slot.Look = key
		apply()
	end
end

local function lookTemplate(slot: SlotRefs)
	look(slot, "empty", function()
		local t = slot.Template
		slot.Label.Text = t.LabelText
		slot.Label.TextColor3 = t.LabelColor
		slot.LightBar.Color = t.BarColor
		slot.LightBar.Material = t.BarMaterial
		slot.Light.Enabled = t.LightEnabled
		slot.Display.Transparency = t.DisplayTransparency
	end)
end

local function clearFishFields(slot: SlotRefs)
	for _, name in FISH_FIELDS do
		setAttr(slot, name, nil)
	end
end

local function showEmpty(refs: BaseRefs, slot: SlotRefs, kind: string?, detail: string?)
	clearFishFields(slot)
	setAttr(slot, "State", "empty")
	lookTemplate(slot)
	if kind then
		event(refs, slot, kind, detail or "")
	end
end

local function showLocked(refs: BaseRefs, slot: SlotRefs, kind: string?)
	clearFishFields(slot)
	setAttr(slot, "State", "locked")
	look(slot, "locked", function()
		local t = slot.Template
		slot.Label.Text = TEXTS.SlotLocked
		slot.Label.TextColor3 = t.LabelColor
		slot.LightBar.Material = Enum.Material.SmoothPlastic
		slot.LightBar.Color = UIConfig.Palette.Slate.Bottom
		slot.Light.Enabled = false
		slot.Display.Transparency = t.DisplayTransparency
	end)
	if kind then
		event(refs, slot, kind, "")
	end
end

local function rarityBarColor(rarity: string): Color3
	if rarity == "Mythic" then
		return UIConfig.Rainbow[6]
	end
	local style = UIConfig.Rarity[rarity]
	return if style then style.Bottom else UIConfig.Rarity.Common.Bottom
end

local function showFish(refs: BaseRefs, slot: SlotRefs, fish: FishRt, kind: string, detail: string)
	local rec = fish.Rec
	setAttr(slot, "FishUid", fish.Uid)
	setAttr(slot, "FishId", rec.Id)
	setAttr(slot, "Rarity", fish.Rarity)
	setAttr(slot, "Mutation", fish.Mutation)
	setAttr(slot, "Kg", rec.Kg)
	setAttr(slot, "Value", fish.Value)
	setAttr(slot, "Income", fish.Income10 / 10)
	setAttr(slot, "GrowFrom", fish.GrowFrom)
	setAttr(slot, "State", "fish")
	look(slot, `fish|{rec.Id}|{fish.Rarity}`, function()
		local def = FishingRules.GetFish(rec.Id)
		local rarity = FishingRules.GetRarity(fish.Rarity)
		slot.Label.Text = if def then def.Name else rec.Id
		slot.Label.TextColor3 = if rarity then rarity.Color else slot.Template.LabelColor
		slot.LightBar.Material = slot.Template.BarMaterial
		slot.LightBar.Color = rarityBarColor(fish.Rarity)
		slot.Light.Enabled = true
		slot.Display.Transparency = TankConfig.Display.GlassOccupied
	end)
	event(refs, slot, kind, detail)
end

-- Витрина index садка rt (подключённого к refs) — как сейчас в данных.
local function showSlot(refs: BaseRefs, rt: Runtime, index: number, kind: string, detail: string)
	local slot = refs.Slots[index]
	local fish = rt.BySlot[index]
	if index > PlayerData.SlotCap(rt.Data) then
		showLocked(refs, slot, kind)
	elseif fish then
		showFish(refs, slot, fish, kind, detail)
	else
		showEmpty(refs, slot, kind, detail)
	end
end

--------------------------------------------------------------------------------
-- Доход и атрибуты
--------------------------------------------------------------------------------

-- После любого изменения садка: сумма дохода, атрибуты игрока и садка, «Доход/с».
local function refresh(rt: Runtime)
	local sum = 0
	for _, fish in rt.BySlot do
		sum += fish.Income10
	end
	rt.Income10Sum = sum
	local player = rt.Player
	local count = activeCount(rt)
	local slots = PlayerData.SlotCap(rt.Data)
	if player:GetAttribute("TankCount") ~= count then
		player:SetAttribute("TankCount", count)
	end
	if player:GetAttribute("TankSlots") ~= slots then
		player:SetAttribute("TankSlots", slots)
	end
	EconomyService:SetIncome(player, if rt.Mounted then sum else 0)
	local base = rt.Base
	local refs = base and baseRefs[base]
	if rt.Mounted and refs then
		setTankAttr(refs, "Count", count)
		setTankAttr(refs, "Slots", slots)
		setTankAttr(refs, "Income", sum / 10)
	end
end

--------------------------------------------------------------------------------
-- Подключение садка к базе
--------------------------------------------------------------------------------

local function mount(rt: Runtime, base: Base)
	if rt.Mounted or base.Owner ~= rt.Player then
		return
	end
	local refs = baseRefs[base]
	if not refs then
		return
	end
	rt.Base = base
	rt.Mounted = true
	refs.Owner = rt
	local now = Workspace:GetServerTimeNow()
	for _, fish in rt.BySlot do
		fish.GrowFrom = TankRules.AttrTime(now - math.clamp(fish.Rec.Age, 0, GROWTH_TIME))
	end
	for index in refs.Slots do
		showSlot(refs, rt, index, "mount", "")
	end
	refresh(rt)
	refs.Prompt.Enabled = true
end

local function unmount(rt: Runtime)
	if not rt.Mounted then
		return
	end
	local base = rt.Base :: Base
	local refs = baseRefs[base]
	local now = Workspace:GetServerTimeNow()
	for _, fish in rt.BySlot do
		fish.Rec.Age = TankRules.AgeAt(fish.GrowFrom, now) -- возраст замирает
	end
	rt.Mounted = false
	rt.Base = nil
	if refs then
		if refs.Owner == rt then
			refs.Owner = nil
		end
		for _, slot in refs.Slots do
			showEmpty(refs, slot, "mount", "")
		end
		setTankAttr(refs, "Count", nil)
		setTankAttr(refs, "Slots", nil)
		setTankAttr(refs, "Income", nil)
		refs.Prompt.Enabled = false
	end
	refresh(rt)
end

local function newRuntime(player: Player, data: PlayerData.Data): Runtime
	local rt: Runtime = {
		Player = player,
		Data = data,
		Fish = {},
		BySlot = {},
		Base = nil,
		Mounted = false,
		Income10Sum = 0,
		Carry10 = 0,
		Ticks = 0,
	}
	local active, dormant = PlayerData.Layout(data)
	for slot, rec in active do
		local fish = activeFish(rec)
		rt.Fish[fish.Uid] = fish
		rt.BySlot[slot] = fish
	end
	for _, rec in dormant do
		rt.Fish[rec.Uid] = {
			Rec = rec,
			Uid = rec.Uid,
			Rarity = "",
			Mutation = nil,
			Value = 0,
			Income10 = 0,
			GrowFrom = 0,
			Locked = false,
			Dormant = true,
		}
	end
	return rt
end

-- Данные и база игрока на месте (что второе) — подключить.
local function tryMount(rt: Runtime)
	local base = BaseService:GetBase(rt.Player)
	if base and base.Owner == rt.Player then
		mount(rt, base)
	end
end

local function onLoaded(player: Player, data: PlayerData.Data)
	if runtimes[player] or player.Parent ~= Players then
		return
	end
	local rt = newRuntime(player, data)
	runtimes[player] = rt
	refresh(rt)
	tryMount(rt)
end

local function onPlayerRemoving(player: Player)
	TankRequests.Forget(player)
	local rt = runtimes[player]
	if not rt then
		return
	end
	unmount(rt)
	if runtimes[player] == rt then
		runtimes[player] = nil
	end
end

--------------------------------------------------------------------------------
-- Рыбы: добавить, убрать
--------------------------------------------------------------------------------

-- Записи и данные, если игрок может их менять (ворота CanWrite), иначе nil.
local function writable(player: Player): (Runtime?, PlayerData.Data?)
	if not DataService:CanWrite(player) then
		return nil, nil
	end
	local rt = runtimes[player]
	local data = DataService:Get(player)
	if not rt or not data or rt.Data ~= data then
		return nil, nil
	end
	return rt, data
end

-- Убрать активную рыбу из данных и записей (без денег, витрин и сигналов).
local function detach(rt: Runtime, fish: FishRt)
	removeEntry(rt.Data, fish.Rec)
	rt.Fish[fish.Uid] = nil
	if rt.BySlot[fish.Rec.Slot] == fish then
		rt.BySlot[fish.Rec.Slot] = nil
	end
end

function TankService:AddFish(player: Player, fish: FishData, reason: string): TankResult?
	local rt, data = writable(player)
	if not rt or not data or type(fish) ~= "table" then
		return nil
	end
	-- 1. Посчитать и проверить (ничего не меняя).
	local id = fish.Id
	local def = if type(id) == "string" then FishingRules.GetFish(id) else nil
	if not def or not finite(fish.Kg) or fish.Kg <= 0 then
		return nil
	end
	local mutation = knownMutation(fish.Mutation)
	local value, income = FishingRules.Price(id, fish.Kg, mutation)
	local income10 = TankRules.Income10(income)
	local now = Workspace:GetServerTimeNow()
	local cap = PlayerData.SlotCap(data)
	local slot: number? = nil
	for index = 1, cap do
		if rt.BySlot[index] == nil then
			slot = index
			break
		end
	end
	local result: "stored" | "replaced" | "sold" = "stored"
	local weak: FishRt? = nil
	local price: number? = nil
	if not slot then
		local candidates: { TankRules.Candidate } = {}
		for _, other in rt.BySlot do
			table.insert(candidates, {
				Uid = other.Uid,
				Income10 = other.Income10,
				Value = other.Value,
				Age = ageOf(rt, other, now),
				Locked = other.Locked,
				Dormant = false,
			})
		end
		local weakUid = TankRules.ChooseReplacement(candidates, income10)
		local chosen = weakUid and rt.Fish[weakUid]
		if chosen then
			weak = chosen
			result = "replaced"
			slot = chosen.Rec.Slot
			price = TankRules.SellPrice(chosen.Value, ageOf(rt, chosen, now), HOME)
		else
			result = "sold"
			price = TankRules.SellPrice(value, 0, HOME)
		end
	end
	if price and not goodPrice(price) then
		warn(
			`[TankService] цена продажи не число ({price}) — улов игрока {player.UserId} не принят`
		)
		return nil
	end

	-- 2. Менять: данные → записи → деньги → статистика → витрина → доход → атрибуты → сигналы.
	local entry: PlayerData.Fish? = nil
	local added: FishRt? = nil
	if weak then
		detach(rt, weak)
	end
	if result ~= "sold" then
		local index: number = slot :: number
		local newEntry: PlayerData.Fish = {
			Uid = PlayerData.NewUid(data),
			Id = id,
			Kg = fish.Kg,
			Mutation = mutation,
			Age = 0,
			Slot = index,
			CaughtAt = os.time(),
		}
		table.insert(data.Tank, newEntry)
		local fishRt = activeFish(newEntry)
		fishRt.GrowFrom = TankRules.AttrTime(now)
		rt.Fish[fishRt.Uid] = fishRt
		rt.BySlot[index] = fishRt
		entry, added = newEntry, fishRt
	end
	if price then
		EconomyService:AddMoney(player, price, "autosell")
		data.Stats.Sold += 1
	end
	local base = rt.Base
	local refs = base and baseRefs[base]
	if rt.Mounted and refs and added then
		local slotRefs = refs.Slots[added.Rec.Slot]
		if weak then
			showFish(refs, slotRefs, added, "swap", string.format("%d", price :: number))
		else
			showFish(refs, slotRefs, added, "in", id)
		end
	end
	refresh(rt)

	local tank: TankResult = {
		Result = result,
		Slot = if added then added.Rec.Slot else nil,
		Uid = if added then added.Uid else nil,
		Count = activeCount(rt),
		Slots = cap,
		Replaced = if weak then soldFish(weak, price :: number) else nil,
		Price = price,
		First = if reason == "catch" and data.Stats.Caught == 1 then true else nil,
	}
	if weak then
		TankService.FishRemoved:Fire(player, table.clone(weak.Rec), "autosell")
	end
	if entry then
		TankService.FishAdded:Fire(player, table.clone(entry), reason)
	end
	if reason ~= "catch" then
		local stored = table.clone(tank) :: any
		stored.Fish = table.clone(fish)
		send(player, "Stored", stored)
	end
	return tank
end

function TankService:RemoveFish(owner: Player, uid: string, reason: string): PlayerData.Fish?
	local rt = writable(owner)
	local fish = rt and type(uid) == "string" and rt.Fish[uid]
	if not rt or not fish or fish.Dormant then
		return nil
	end
	detach(rt, fish)
	local base = rt.Base
	local refs = base and baseRefs[base]
	if rt.Mounted and refs then
		showEmpty(refs, refs.Slots[fish.Rec.Slot], if reason == "stolen" then "stolen" else "mount", "")
	end
	refresh(rt)
	local copy = table.clone(fish.Rec)
	TankService.FishRemoved:Fire(owner, copy, reason)
	return copy
end

function TankService:SetLocked(owner: Player, uid: string, locked: boolean): boolean
	local rt = runtimes[owner]
	local fish = rt and rt.Fish[uid]
	if not fish or fish.Dormant then
		return false
	end
	fish.Locked = locked == true
	return true
end

function TankService:SetSlots(player: Player, slots: number): boolean
	local rt, data = writable(player)
	if not rt or not data or not finite(slots) or slots % 1 ~= 0 or slots < data.TankSlots then
		return false
	end
	local before = PlayerData.SlotCap(data)
	data.TankSlots = slots
	local cap = PlayerData.SlotCap(data)
	-- Спящие знакомые рыбы — в новые свободные витрины (по порядку Tank).
	for _, rec in data.Tank do
		local fish = rt.Fish[rec.Uid]
		if fish and fish.Dormant and FishingRules.GetFish(rec.Id) then
			for index = 1, cap do
				if rt.BySlot[index] == nil then
					rec.Slot = index
					local awake = activeFish(rec)
					if rt.Mounted then
						awake.GrowFrom =
							TankRules.AttrTime(Workspace:GetServerTimeNow() - math.clamp(rec.Age, 0, GROWTH_TIME))
					end
					rt.Fish[rec.Uid] = awake
					rt.BySlot[index] = awake
					break
				end
			end
		end
	end
	local base = rt.Base
	local refs = base and baseRefs[base]
	if rt.Mounted and refs then
		for index = 1, cap do
			if index > before or rt.BySlot[index] ~= nil then
				showSlot(refs, rt, index, "mount", "")
			end
		end
	end
	refresh(rt)
	return true
end

--------------------------------------------------------------------------------
-- Запросы клиента
--------------------------------------------------------------------------------

local function onTankSell(player: Player, rawUid: unknown)
	if TankRules.UidNumber(rawUid) == nil then
		return -- не номер рыбы: молча
	end
	if not TankRequests.Take(player) then
		return -- лимит: молча (и без ответа)
	end
	local uid = rawUid :: string
	local rt, data = writable(player)
	if not rt or not data then
		deny(player, "loading")
		return
	end
	if not rt.Mounted then
		deny(player, "nobase")
		return
	end
	local fish = rt.Fish[uid]
	if not fish or fish.Dormant or rt.BySlot[fish.Rec.Slot] ~= fish then
		deny(player, "missing")
		return
	end
	if fish.Locked then
		deny(player, "locked")
		return
	end
	local ratePct, place = MarketService:RatePct(player)
	local price = TankRules.SellPrice(fish.Value, ageOf(rt, fish, Workspace:GetServerTimeNow()), ratePct)
	if not goodPrice(price) then
		warn(
			`[TankService] цена продажи не число ({price}) — продажа {uid} игрока {player.UserId} отменена`
		)
		return
	end
	-- Менять (без ожиданий): данные → деньги → статистика → витрина → доход → remote → сигнал.
	detach(rt, fish)
	EconomyService:AddMoney(player, price, "sell")
	data.Stats.Sold += 1
	local refs = baseRefs[rt.Base :: Base]
	if refs then
		showEmpty(refs, refs.Slots[fish.Rec.Slot], "sold", string.format("%d", price))
	end
	refresh(rt)
	send(player, "Sold", {
		Items = { soldFish(fish, price) },
		Amount = price,
		RatePct = ratePct,
		Place = place,
	})
	TankService.FishRemoved:Fire(player, table.clone(fish.Rec), "sell")
end

local function onTankPrompt(refs: BaseRefs, player: Player)
	if not TankRequests.Take(player) then
		return
	end
	if refs.Base.Owner ~= player then
		return -- чужая база: кнопка только хозяину
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	if (refs.PromptAttachment.WorldPosition - root.Position).Magnitude > PROMPT.MaxDistance + PROMPT.Slack then
		return
	end
	local rate = player:GetAttribute("SellRatePct")
	send(player, "Open", {
		Place = "Tank",
		RatePct = if type(rate) == "number" then rate else HOME,
		Name = PROMPT.Object,
	})
end

--------------------------------------------------------------------------------
-- Цикл дохода
--------------------------------------------------------------------------------

local function tickPlayer(player: Player, rt: Runtime, ticks: number, now: number)
	if not rt.Mounted or not DataService:CanWrite(player) then
		return
	end
	rt.Ticks += ticks
	rt.Carry10 += ticks * rt.Income10Sum
	local whole = rt.Carry10 // 10
	rt.Carry10 -= whole * 10
	if whole > 0 then
		EconomyService:AddMoney(player, whole, "income")
	end
	for _, fish in rt.BySlot do
		fish.Rec.Age = TankRules.AgeAt(fish.GrowFrom, now)
	end
	MarketService:Sample(player)
end

local function incomeLoop()
	local tick = EconomyConfig.IncomeTick
	local acc = 0
	while true do
		local dt = task.wait(tick)
		acc += dt
		local ticks = math.floor(acc / tick)
		acc -= ticks * tick
		ticks = math.min(ticks, EconomyConfig.MaxCatchUp)
		if ticks > 0 then
			local now = Workspace:GetServerTimeNow()
			for player, rt in runtimes do
				local ok, err = xpcall(function(): any
					tickPlayer(player, rt, ticks, now)
					return nil
				end, trace)
				if not ok and os.clock() - lastLoopWarn >= WARN_EVERY then
					lastLoopWarn = os.clock()
					warn(`[TankService] ❌ тик дохода игрока {player.UserId}: {err}`)
				end
			end
		end
	end
end

-- Хук сохранения (внутри transform DataService, не ждёт): свежий возраст рыб подключённого
-- садка. Этап 4: вернуть skipUid для рыб «в пути».
local function onSerialize(player: Player, data: PlayerData.Data): ((uid: string) -> boolean)?
	local rt = runtimes[player]
	if rt and rt.Data == data and rt.Mounted then
		local now = Workspace:GetServerTimeNow()
		for _, fish in rt.BySlot do
			fish.Rec.Age = TankRules.AgeAt(fish.GrowFrom, now)
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Тесты
--------------------------------------------------------------------------------

function TankService._debugSizes(): { [string]: number }
	local records, mounted = 0, 0
	for _ in runtimes do
		records += 1
	end
	for _, refs in baseRefs do
		if refs.Owner then
			mounted += 1
		end
	end
	return { Records = records, Bases = mounted, Requests = TankRequests.Size() }
end

function TankService._runtimeFor(player: Player): any
	return runtimes[player]
end

--------------------------------------------------------------------------------
-- Жизненный цикл сервиса
--------------------------------------------------------------------------------

local function required(root: Instance, path: { string }, className: string): any
	local node: Instance = root
	for _, name in path do
		local child = node:FindFirstChild(name)
		if not child then
			error(`[TankService] в {root:GetFullName()} нет {table.concat(path, ".")}`)
		end
		node = child
	end
	if not node:IsA(className) then
		error(`[TankService] {node:GetFullName()} должен быть {className}, а это {node.ClassName}`)
	end
	return node
end

local function resolveBase(base: Base): BaseRefs
	local slots: { SlotRefs } = {}
	local tank = base.Tank
	for index = 1, TankConfig.MaxSlots do
		local name = `Slot_{index}`
		local model = required(tank, { "Slots", name }, "Model") :: Model
		required(model, { "Display", "FishPoint" }, "Attachment")
		local display = required(model, { "Display" }, "BasePart") :: BasePart
		local label = required(model, { "Pedestal", "LabelGui", "Label" }, "TextLabel") :: TextLabel
		local bar = required(model, { "LightBar" }, "BasePart") :: BasePart
		local light = bar:FindFirstChildOfClass("SurfaceLight")
		if not light then
			error(`[TankService] у {bar:GetFullName()} нет SurfaceLight`)
		end
		local slot: SlotRefs = {
			Index = index,
			Model = model,
			Display = display,
			Label = label,
			LightBar = bar,
			Light = light,
			Template = {
				LabelText = TEXTS.SlotEmpty,
				LabelColor = label.TextColor3,
				BarColor = bar.Color,
				BarMaterial = bar.Material,
				LightEnabled = light.Enabled,
				DisplayTransparency = display.Transparency,
			},
			Attrs = {},
			Look = "",
		}
		slots[index] = slot
	end
	local attachment = base.TankPromptAttachment
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TankPrompt"
	prompt.ActionText = PROMPT.Action
	prompt.ObjectText = PROMPT.Object
	prompt.HoldDuration = PROMPT.HoldDuration
	prompt.MaxActivationDistance = PROMPT.MaxDistance
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = attachment
	local refs: BaseRefs = {
		Base = base,
		Slots = slots,
		Prompt = prompt,
		PromptAttachment = attachment,
		Serial = 0,
		Owner = nil,
		TankAttrs = {},
	}
	for _, slot in slots do
		showEmpty(refs, slot, nil, nil)
	end
	return refs
end

function TankService:Init()
	tankEvent = Net.Event("TankEvent")
	for _, base in BaseService:GetBases() do
		baseRefs[base] = resolveBase(base)
	end
	if type(DataService.OnSerialize) == "function" then
		DataService:OnSerialize(onSerialize)
	end
end

function TankService:Start()
	for _, refs in baseRefs do
		refs.Prompt.Triggered:Connect(function(player: Player)
			onTankPrompt(refs, player)
		end)
	end
	DataService.Loaded:Connect(onLoaded)
	BaseService.BaseAssigned:Connect(function(player: Player, _base: Base)
		local rt = runtimes[player]
		if rt then
			tryMount(rt)
		end
	end)
	BaseService.BaseReleased:Connect(function(player: Player, base: Base)
		local rt = runtimes[player]
		if rt and rt.Base == base then
			unmount(rt)
		end
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	Net.Event("TankSell").OnServerEvent:Connect(onTankSell)
	if type(FishingService.SetCatchSink) == "function" then
		FishingService.SetCatchSink(function(player: Player, fish: FishData): any
			local rt = runtimes[player]
			if not rt or not rt.Mounted or not DataService:CanWrite(player) then
				return nil
			end
			return TankService:AddFish(player, fish, "catch")
		end)
	end
	-- Уже загруженные (Studio: игрок успел раньше скрипта).
	for _, player in Players:GetPlayers() do
		local data = DataService:IsLoaded(player) and DataService:Get(player)
		if data then
			onLoaded(player, data)
		end
	end
	task.spawn(incomeLoop)
end

return TankService
