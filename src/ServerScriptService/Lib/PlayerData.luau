--!strict
--[[
	PlayerData — схема сохранения игрока v1 (Этап 3): чистые функции без состояния, без DataStore
	и без warn (DataStore и предупреждения — DataService). Хранилище DataConfig.StoreName (в
	Studio — с StudioSuffix: StoreNameFor), ключ KeyFor(UserId) = «Player_<UserId>», значение:
	  {
	    V = 1,                 версия схемы (DataConfig.Version)
	    Money = 0,             целые монеты 0..EconomyConfig.MaxMoney (пишет только EconomyService)
	    RodId = "RodBamboo",   удочка («уровень удочки» — её Tier в RodConfig); Этап 5 добавит
	                           купленные удочки
	    TankSlots = 6,         открытых витрин (≥ TankConfig.StartSlots; в игре — не больше MaxSlots)
	    LockLevel = 0,         уровень замка (Этап 4); 0 — нет
	    Upgrades = {},         покупки Этапов 4–5 (Dog, Alarm, Shield, …): ключи — строки
	    Tank = {               ПЛОТНЫЙ массив рыб, порядок не важен:
	      { Uid = "f7", Id = "Perch", Kg = 1.23, Mutation = "Gold", Age = 212.4, Slot = 2,
	        CaughtAt = 1700000123 },   (+ Этап 4: Origin = "<UserId жертвы>:<uid>" у краденой)
	    },
	    NextUid = 8,           номер следующей рыбы ("f8"); номера не повторяются
	    Stats = { Caught = 0, Sold = 0, Earned = 0, Spent = 0, Species = { [FishId] = поймано } },
	                           всегда Money == StartMoney + Earned − Spent (Ledger — ловушка дюпа)
	    Created = 0, LastOnline = 0, SaveCount = 0,   os.time() первой загрузки и последнего
	                           сохранения (на будущее: доход офлайн), число сохранений
	    Session = { Id, Server, Job, T },   замок сессии (DataService); nil — свободно
	  }
	Рыба: Uid ("f<номер>", ≤ 12 знаков), Id (FishConfig), Mutation (нет — без мутации), Kg, Age
	(секунд в садке, до TankConfig.Growth.Time, с десятыми), Slot (1..TankSlots, у каждой активной
	рыбы свой), CaughtAt (os.time, справочно), Origin (Этап 4). Rarity, Value и Income НЕ
	хранятся: сервер считает их при загрузке (FishingRules.Price) — новый баланс действует и на
	сохранённых рыб, а испорченное сохранение не даст дохода. Всё, что живёт только в игре
	(GrowFrom, Locked, Dormant, Income10, остаток дохода, …), — в таблицах сервисов, не здесь;
	ключи с «_» не сохраняются никогда.

	API:
	  Template() -> Data                  данные нового игрока (каждый раз новая таблица)
	  Reconcile(data) -> data             дописывает недостающие поля шаблона — только в словарях
	                                      (массив Tank — только если его нет совсем, без слияния по
	                                      элементам); чужие поля остаются
	  Migrate(data) -> data               MIGRATIONS[v](data), пока V < Version (в v1 — пусто;
	                                      нет V или он испорчен — это 1)
	  Sanitize(data) -> (data, issues)    чинит только то, что точно неверно, и никогда не ломает
	                                      то, чего этот сервер не понимает (правила ниже)
	  Serialize(data, opts?) -> (out, issues)  новая таблица для UpdateAsync — белый список
	                                      известных полей с проверкой типов (плохое значение →
	                                      по шаблону + issue) и незнакомые поля (их записал сервер
	                                      новее), только если они JSON-совместимы: строки, логические,
	                                      конечные числа, плотные массивы и словари со строковыми
	                                      ключами, не глубже DataConfig.Limits.MaxDepth; остальное
	                                      выброшено + issue. opts.skipUid(uid) → true: рыбу не
	                                      сохранять (Этап 4, «в пути» при краже); opts.strict —
	                                      без незнакомых полей вовсе (повтор после ошибки 103/104/105)
	  NewUid(data) -> string              номер новой рыбы ("f" .. NextUid; NextUid += 1)
	  SlotCap(data) -> number             витрин в игре: min(TankSlots, MaxSlots)
	  Layout(data) -> (active, dormant)   кто где: active[slot] = рыба (вид знаком, Slot — целое
	                                      1..SlotCap, первая в порядке Tank); dormant — остальные
	                                      («спят»: не видны, без дохода, не продаются и не
	                                      заменяются, сохраняются как есть — TankService)
	  StoreNameFor(isStudio) -> string    "PlayerData" | "PlayerData_Studio"
	  KeyFor(userId) -> string            "Player_<UserId>"
	  Ledger(data) -> (ok, expected)      Money == StartMoney + Stats.Earned − Stats.Spent?
	                                      (не чинится никогда: расхождение — признак дюпа или ошибки)
	issues — список строк «путь: что было → что стало» (DataService пишет их в warn; одно
	предупреждение на путь за сессию).

	Правила Sanitize (Roblox держит старые серверы после публикации: старый сервер, загрузив
	данные сервера новее, не должен их выбросить, обнулить или продать — и записать так обратно):
	  • числа — num(x, по умолчанию, min, max): не число, NaN и ±inf → по умолчанию, потом обрезка
	    (math.clamp(NaN, a, b) в Luau — NaN); Money — целое 0..MaxMoney; TankSlots — целое, обрезается
	    только снизу (StartSlots: 16 слотов сервера новее остаются 16); LockLevel — целое ≥ 0;
	  • Upgrades — словарь со строковыми ключами (иначе {}); RodId — строка, незнакомая остаётся как
	    есть (в игре — стартовая удочка; сохранённую меняет только FishingService:SetRod);
	  • Tank — словарь или массив с дырами переупаковывается плотно; рыба без строкового Id или без
	    конечного Kg > 0 выбрасывается; незнакомый Id и незнакомая мутация остаются как есть (в игре
	    — «спит» / без мутации); Age — 0..Growth.Time; плохой или повторный Uid — новый (NewUid);
	    NextUid ≥ 1 + самый большой номер;
	  • витрины: знакомая рыба сохраняет целый Slot 1..SlotCap, если он ни у кого раньше; рыбы с
	    повторным или неверным слотом встают в самые младшие свободные; свободных нет — «спит»,
	    Slot не меняется (вернётся, когда витрина освободится: проверка при каждой загрузке).
	    Sanitize НИЧЕГО не продаёт;
	  • Stats — числа ≥ 0 целые; Species — строковые ключи, целые значения ≥ 0.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local DataConfig = require(Config:WaitForChild("DataConfig"))
local EconomyConfig = require(Config:WaitForChild("EconomyConfig"))
local RodConfig = require(Config:WaitForChild("RodConfig"))
local TankConfig = require(Config:WaitForChild("TankConfig"))
local FishingRules = require(Shared:WaitForChild("FishingRules"))
local TankRules = require(Shared:WaitForChild("TankRules"))

export type Fish = {
	Uid: string,
	Id: string,
	Kg: number,
	Mutation: string?,
	Age: number,
	Slot: number,
	CaughtAt: number,
	Origin: string?,
}

export type Stats = {
	Caught: number,
	Sold: number,
	Earned: number,
	Spent: number,
	Species: { [string]: number },
}

export type Session = { Id: string, Server: string, Job: string, T: number }

export type Data = {
	V: number,
	Money: number,
	RodId: string,
	TankSlots: number,
	LockLevel: number,
	Upgrades: { [string]: any },
	Tank: { Fish },
	NextUid: number,
	Stats: Stats,
	Created: number,
	LastOnline: number,
	SaveCount: number,
	Session: Session?,
}

export type SerializeOptions = {
	skipUid: ((uid: string) -> boolean)?,
	strict: boolean?,
}

local LIMITS = DataConfig.Limits
local GROWTH_TIME = TankConfig.Growth.Time

-- Шаги миграции: MIGRATIONS[v](data) переводит данные версии v в v + 1 (в v1 — ни одного).
local MIGRATIONS: { [number]: (data: any) -> () } = {}

-- Поля верхнего уровня, которые знает эта версия схемы (остальные — «чужие»).
local KNOWN = {
	V = true,
	Money = true,
	RodId = true,
	TankSlots = true,
	LockLevel = true,
	Upgrades = true,
	Tank = true,
	NextUid = true,
	Stats = true,
	Created = true,
	LastOnline = true,
	SaveCount = true,
	Session = true,
}
-- Числовые поля верхнего уровня (Serialize: конечное число, иначе — по шаблону).
local NUMBERS = { "V", "Money", "TankSlots", "LockLevel", "NextUid", "Created", "LastOnline", "SaveCount" }
local STAT_NUMBERS = { "Caught", "Sold", "Earned", "Spent" }
local KNOWN_STATS = { Caught = true, Sold = true, Earned = true, Spent = true, Species = true }
local KNOWN_FISH = {
	Uid = true,
	Id = true,
	Kg = true,
	Mutation = true,
	Age = true,
	Slot = true,
	CaughtAt = true,
	Origin = true,
}
-- Массивы верхнего уровня: Reconcile их не сливает по элементам.
local ARRAYS = { Tank = true }

local PlayerData = {}

--------------------------------------------------------------------------------
-- Помощники
--------------------------------------------------------------------------------

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

-- Число из сохранения: не число / NaN / ±inf → default, потом обрезка min..max.
local function num(x: any, default: number, min: number?, max: number?): number
	if not finite(x) then
		return default
	end
	local value: number = x
	if min and value < min then
		value = min
	end
	if max and value > max then
		value = max
	end
	return value
end

-- Короткое описание значения для issue.
local function describe(x: any): string
	local kind = typeof(x)
	if kind == "string" then
		local text: string = x
		return if #text > 24 then string.format("%q…", string.sub(text, 1, 24)) else string.format("%q", text)
	elseif kind == "number" or kind == "boolean" or kind == "nil" then
		return tostring(x)
	end
	return kind
end

-- Пары таблицы плотным списком: числовые ключи по возрастанию, потом строковые, потом прочие.
-- packed — таблица уже была плотным массивом 1..n.
local function pack(t: { [any]: any }): ({ any }, boolean)
	local keys = {}
	for key in t do
		table.insert(keys, key)
	end
	local function rank(key: any): number
		return if type(key) == "number" then 0 elseif type(key) == "string" then 1 else 2
	end
	table.sort(keys, function(a: any, b: any): boolean
		local ra, rb = rank(a), rank(b)
		if ra ~= rb then
			return ra < rb
		elseif ra == 2 then
			return tostring(a) < tostring(b)
		end
		return a < b
	end)
	local list = {}
	local packed = true
	for i, key in keys do
		if key ~= i then
			packed = false
		end
		table.insert(list, t[key])
	end
	return list, packed
end

local function startsWithUnderscore(key: string): boolean
	return string.sub(key, 1, 1) == "_"
end

-- JSON-совместимая копия чужого значения (или false + issue): строки, логические, конечные
-- числа, плотные массивы, словари со строковыми ключами; ключи с «_» пропускаются.
local function jsonCopy(value: any, depth: number, path: string, issues: { string }): (boolean, any)
	local kind = typeof(value)
	if kind == "string" or kind == "boolean" then
		return true, value
	elseif kind == "number" then
		if finite(value) then
			return true, value
		end
		table.insert(issues, `{path}: {describe(value)} → выброшено (не конечное число)`)
		return false, nil
	elseif kind ~= "table" then
		table.insert(issues, `{path}: {kind} → выброшено (не JSON)`)
		return false, nil
	end
	if depth > LIMITS.MaxDepth then
		table.insert(issues, `{path}: глубже {LIMITS.MaxDepth} уровней → выброшено`)
		return false, nil
	end
	local count, maxIndex, strings, numbers = 0, 0, 0, 0
	for key in value do
		count += 1
		if type(key) == "string" then
			strings += 1
		elseif type(key) == "number" and key % 1 == 0 and key >= 1 then
			numbers += 1
			maxIndex = math.max(maxIndex, key)
		else
			table.insert(issues, `{path}: ключ {describe(key)} → выброшено (не JSON)`)
			return false, nil
		end
	end
	local copy = {}
	if count == 0 then
		return true, copy
	elseif numbers == count and maxIndex == count then
		for i = 1, count do
			local ok, item = jsonCopy(value[i], depth + 1, `{path}[{i}]`, issues)
			if ok then
				table.insert(copy, item)
			end
		end
		return true, copy
	elseif strings == count then
		for key, item in value do
			if not startsWithUnderscore(key) then
				local ok, itemCopy = jsonCopy(item, depth + 1, `{path}.{key}`, issues)
				if ok then
					copy[key] = itemCopy
				end
			end
		end
		return true, copy
	end
	table.insert(
		issues,
		`{path}: смешанная таблица или массив с дырами → выброшено (не JSON)`
	)
	return false, nil
end

-- Чужие поля словаря source (не из known) — в target, если JSON-совместимы (strict — никаких).
local function copyUnknown(
	source: { [any]: any },
	target: { [string]: any },
	known: { [string]: boolean },
	path: string,
	strict: boolean,
	issues: { string }
)
	for key, value in source do
		if type(key) == "string" and known[key] then
			continue
		end
		local where = if path == "" then tostring(key) else `{path}.{tostring(key)}`
		if type(key) ~= "string" then
			table.insert(issues, `{where}: ключ {describe(key)} → выброшено (не строка)`)
		elseif startsWithUnderscore(key) then
			continue -- служебное поле игры: не сохраняется никогда
		elseif strict then
			table.insert(issues, `{where}: незнакомое поле → выброшено (strict)`)
		else
			local ok, copy = jsonCopy(value, 1, where, issues)
			if ok then
				target[key] = copy
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Шаблон, дополнение, миграции
--------------------------------------------------------------------------------

function PlayerData.Template(): Data
	return {
		V = DataConfig.Version,
		Money = EconomyConfig.StartMoney,
		RodId = RodConfig.StartRod,
		TankSlots = TankConfig.StartSlots,
		LockLevel = 0,
		Upgrades = {},
		Tank = {},
		NextUid = 1,
		Stats = { Caught = 0, Sold = 0, Earned = 0, Spent = 0, Species = {} },
		Created = 0,
		LastOnline = 0,
		SaveCount = 0,
		Session = nil,
	}
end

local function fill(target: { [any]: any }, template: { [any]: any }, top: boolean)
	for key, value in template do
		local current = target[key]
		if current == nil then
			target[key] = value -- (шаблон — новая таблица: делиться нечем)
		elseif type(value) == "table" and type(current) == "table" and not (top and ARRAYS[key]) then
			fill(current, value, false)
		end
	end
end

function PlayerData.Reconcile(data: any): any
	fill(data, PlayerData.Template() :: any, true)
	return data
end

function PlayerData.Migrate(data: any): any
	local v = data.V
	local version = if finite(v) and v >= 1 then math.floor(v) else 1
	while version < DataConfig.Version do
		local step = MIGRATIONS[version]
		assert(step, `[PlayerData] нет миграции v{version} → v{version + 1}`)
		step(data)
		version += 1
	end
	if not (finite(v) and v > DataConfig.Version) then
		data.V = version -- (данные новее сервера не трогаем: DataService их и не грузит)
	end
	return data
end

--------------------------------------------------------------------------------
-- Номера рыб и витрины
--------------------------------------------------------------------------------

function PlayerData.NewUid(data: any): string
	local n = math.floor(num(data.NextUid, 1, 1))
	data.NextUid = n + 1
	return TankRules.UidOf(n)
end

function PlayerData.SlotCap(data: any): number
	return math.min(math.floor(num(data.TankSlots, TankConfig.StartSlots, TankConfig.StartSlots)), TankConfig.MaxSlots)
end

local function validSlot(slot: any, cap: number): boolean
	return finite(slot) and slot % 1 == 0 and slot >= 1 and slot <= cap
end

function PlayerData.Layout(data: any): ({ [number]: Fish }, { Fish })
	local cap = PlayerData.SlotCap(data)
	local active: { [number]: Fish } = {}
	local dormant: { Fish } = {}
	for _, fish in data.Tank do
		local slot = fish.Slot
		if FishingRules.GetFish(fish.Id) ~= nil and validSlot(slot, cap) and active[slot] == nil then
			active[slot] = fish
		else
			table.insert(dormant, fish)
		end
	end
	return active, dormant
end

--------------------------------------------------------------------------------
-- Починка
--------------------------------------------------------------------------------

function PlayerData.Sanitize(data: any): (Data, { string })
	local issues: { string } = {}
	local function report(path: string, was: any, now: any)
		table.insert(issues, `{path}: {describe(was)} → {describe(now)}`)
	end
	local function wholeField(
		container: { [string]: any },
		path: string,
		key: string,
		default: number,
		min: number?,
		max: number?
	)
		local was = container[key]
		local now = math.floor(num(was, default, min, max))
		if now ~= was then
			report(path, was, now)
		end
		container[key] = now
	end

	-- Верхний уровень
	wholeField(data, "Money", "Money", EconomyConfig.StartMoney, 0, EconomyConfig.MaxMoney)
	wholeField(data, "TankSlots", "TankSlots", TankConfig.StartSlots, TankConfig.StartSlots)
	wholeField(data, "LockLevel", "LockLevel", 0, 0)
	wholeField(data, "Created", "Created", 0, 0)
	wholeField(data, "LastOnline", "LastOnline", 0, 0)
	wholeField(data, "SaveCount", "SaveCount", 0, 0)
	if type(data.RodId) ~= "string" or data.RodId == "" then
		report("RodId", data.RodId, RodConfig.StartRod)
		data.RodId = RodConfig.StartRod
	end
	if type(data.Upgrades) ~= "table" then
		report("Upgrades", data.Upgrades, "{}")
		data.Upgrades = {}
	else
		for key in table.clone(data.Upgrades) do
			if type(key) ~= "string" then
				report(`Upgrades[{describe(key)}]`, key, nil)
				data.Upgrades[key] = nil
			end
		end
	end

	-- Статистика
	if type(data.Stats) ~= "table" then
		report("Stats", data.Stats, "шаблон")
		data.Stats = PlayerData.Template().Stats
	end
	local stats = data.Stats
	for _, key in STAT_NUMBERS do
		wholeField(stats, `Stats.{key}`, key, 0, 0)
	end
	if type(stats.Species) ~= "table" then
		report("Stats.Species", stats.Species, "{}")
		stats.Species = {}
	else
		local species = stats.Species
		for key, count in table.clone(species) do
			if type(key) ~= "string" then
				report(`Stats.Species[{describe(key)}]`, count, nil)
				species[key] = nil
			else
				wholeField(species, `Stats.Species.{key}`, key, 0, 0)
			end
		end
	end

	-- Садок: плотный массив, только рыбы с Id и Kg
	local tank = data.Tank
	if type(tank) ~= "table" then
		report("Tank", tank, "{}")
		tank = {}
	end
	local list, packed = pack(tank)
	if not packed then
		table.insert(issues, "Tank: не плотный массив → переупакован")
	end
	local fishes: { any } = {}
	local paths: { string } = {}
	for i, fish in list do
		local path = `Tank[{i}]`
		if
			type(fish) ~= "table"
			or type(fish.Id) ~= "string"
			or fish.Id == ""
			or not finite(fish.Kg)
			or fish.Kg <= 0
		then
			table.insert(issues, `{path}: {describe(fish)} без Id или Kg → выброшена`)
			continue
		end
		local age = num(fish.Age, 0, 0, GROWTH_TIME)
		if age ~= fish.Age then
			report(`{path}.Age`, fish.Age, age)
			fish.Age = age
		end
		if fish.Mutation ~= nil and type(fish.Mutation) ~= "string" then
			report(`{path}.Mutation`, fish.Mutation, nil)
			fish.Mutation = nil
		end
		if fish.Origin ~= nil and type(fish.Origin) ~= "string" then
			report(`{path}.Origin`, fish.Origin, nil)
			fish.Origin = nil
		end
		local caught = num(fish.CaughtAt, 0, 0)
		if caught ~= fish.CaughtAt then
			report(`{path}.CaughtAt`, fish.CaughtAt, caught)
			fish.CaughtAt = caught
		end
		if not finite(fish.Slot) then
			report(`{path}.Slot`, fish.Slot, 0)
			fish.Slot = 0
		end
		table.insert(fishes, fish)
		table.insert(paths, path)
	end
	data.Tank = fishes

	-- Номера: первый владелец номера его сохраняет, плохие и повторные получают новые
	local seen: { [string]: boolean } = {}
	local highest = 0
	local renumber: { number } = {}
	for i, fish in fishes do
		local n = TankRules.UidNumber(fish.Uid)
		if n and not seen[fish.Uid] then
			seen[fish.Uid] = true
			highest = math.max(highest, n)
		else
			table.insert(renumber, i)
		end
	end
	local nextUid = math.floor(num(data.NextUid, 1, 1))
	if nextUid < highest + 1 or nextUid ~= data.NextUid then
		local fixed = math.max(nextUid, highest + 1)
		report("NextUid", data.NextUid, fixed)
		nextUid = fixed
	end
	data.NextUid = nextUid
	for _, i in renumber do
		local fish = fishes[i]
		local uid = PlayerData.NewUid(data)
		while seen[uid] do
			uid = PlayerData.NewUid(data)
		end
		seen[uid] = true
		report(`{paths[i]}.Uid`, fish.Uid, uid)
		fish.Uid = uid
	end

	-- Витрины: знакомые рыбы — свой слот 1..cap или младший свободный; иначе «спит» как есть
	local cap = PlayerData.SlotCap(data)
	local taken: { [number]: boolean } = {}
	local homeless: { number } = {}
	for i, fish in fishes do
		if FishingRules.GetFish(fish.Id) == nil then
			continue -- незнакомый вид: «спит», слот не занимает
		end
		if validSlot(fish.Slot, cap) and not taken[fish.Slot] then
			taken[fish.Slot] = true
		else
			table.insert(homeless, i)
		end
	end
	for _, i in homeless do
		local fish = fishes[i]
		for slot = 1, cap do
			if not taken[slot] then
				taken[slot] = true
				report(`{paths[i]}.Slot`, fish.Slot, slot)
				fish.Slot = slot
				break
			end
		end
		-- (свободных нет — рыба «спит», Slot прежний: Layout)
	end

	return data :: Data, issues
end

--------------------------------------------------------------------------------
-- Сохранение
--------------------------------------------------------------------------------

function PlayerData.Serialize(data: any, opts: SerializeOptions?): ({ [string]: any }, { string })
	local options: SerializeOptions = opts or {}
	local strict = options.strict == true
	local skipUid = options.skipUid
	local issues: { string } = {}
	local template = PlayerData.Template() :: any
	local out: { [string]: any } = {}

	local function number(source: any, key: string, default: number, path: string): number
		local value = source[key]
		if finite(value) then
			return value
		end
		table.insert(issues, `{path}: {describe(value)} → {describe(default)}`)
		return default
	end
	local function text(value: any, maxLength: number): boolean
		return type(value) == "string" and #value <= maxLength
	end

	for _, key in NUMBERS do
		out[key] = number(data, key, template[key], key)
	end
	if text(data.RodId, LIMITS.MaxString) and data.RodId ~= "" then
		out.RodId = data.RodId
	else
		table.insert(issues, `RodId: {describe(data.RodId)} → {describe(template.RodId)}`)
		out.RodId = template.RodId
	end

	-- Upgrades: словарь со строковыми ключами, значения — JSON-совместимые
	local upgrades = {}
	if type(data.Upgrades) == "table" then
		copyUnknown(data.Upgrades, upgrades, {}, "Upgrades", false, issues)
	else
		table.insert(issues, "Upgrades: " .. describe(data.Upgrades) .. " → {}")
	end
	out.Upgrades = upgrades

	-- Садок: плотный массив, известные поля с проверкой, чужие поля — если JSON
	local tank = {}
	if type(data.Tank) == "table" then
		local list, packed = pack(data.Tank)
		if not packed then
			table.insert(issues, "Tank: не плотный массив → переупакован")
		end
		for i, fish in list do
			local path = `Tank[{i}]`
			if type(fish) ~= "table" then
				table.insert(issues, `{path}: {describe(fish)} → выброшено`)
				continue
			end
			if TankRules.UidNumber(fish.Uid) == nil then
				table.insert(issues, `{path}.Uid: {describe(fish.Uid)} → рыба выброшена`)
				continue
			end
			if skipUid and skipUid(fish.Uid) then
				continue -- (Этап 4: рыба «в пути» — её сохранит другой ключ)
			end
			if not text(fish.Id, LIMITS.MaxString) or fish.Id == "" then
				table.insert(issues, `{path}.Id: {describe(fish.Id)} → рыба выброшена`)
				continue
			end
			if not finite(fish.Kg) or fish.Kg <= 0 then
				table.insert(issues, `{path}.Kg: {describe(fish.Kg)} → рыба выброшена`)
				continue
			end
			local copy: { [string]: any } = { Uid = fish.Uid, Id = fish.Id, Kg = fish.Kg }
			if fish.Mutation ~= nil then
				if text(fish.Mutation, LIMITS.MaxString) then
					copy.Mutation = fish.Mutation
				else
					table.insert(issues, `{path}.Mutation: {describe(fish.Mutation)} → нет`)
				end
			end
			copy.Age = math.round(number(fish, "Age", 0, `{path}.Age`) * 10) / 10
			copy.Slot = number(fish, "Slot", 0, `{path}.Slot`)
			copy.CaughtAt = number(fish, "CaughtAt", 0, `{path}.CaughtAt`)
			if fish.Origin ~= nil then
				if text(fish.Origin, LIMITS.OriginMax) then
					copy.Origin = fish.Origin
				else
					table.insert(issues, `{path}.Origin: {describe(fish.Origin)} → нет`)
				end
			end
			copyUnknown(fish, copy, KNOWN_FISH, path, strict, issues)
			table.insert(tank, copy)
		end
	else
		table.insert(issues, "Tank: " .. describe(data.Tank) .. " → {}")
	end
	out.Tank = tank

	-- Статистика
	local stats: { [string]: any } = {}
	local source = data.Stats
	if type(source) ~= "table" then
		table.insert(issues, `Stats: {describe(source)} → шаблон`)
		source = template.Stats
	end
	for _, key in STAT_NUMBERS do
		stats[key] = number(source, key, 0, `Stats.{key}`)
	end
	local species = {}
	if type(source.Species) == "table" then
		for key, count in source.Species do
			if type(key) == "string" and finite(count) then
				species[key] = count
			else
				table.insert(issues, `Stats.Species[{describe(key)}]: {describe(count)} → выброшено`)
			end
		end
	else
		table.insert(issues, "Stats.Species: " .. describe(source.Species) .. " → {}")
	end
	stats.Species = species
	copyUnknown(source, stats, KNOWN_STATS, "Stats", strict, issues)
	out.Stats = stats

	-- Замок сессии (DataService всё равно ставит свой)
	local session = data.Session
	if
		type(session) == "table"
		and text(session.Id, LIMITS.MaxString)
		and text(session.Server, LIMITS.MaxString)
		and text(session.Job, LIMITS.MaxString)
		and finite(session.T)
	then
		out.Session = { Id = session.Id, Server = session.Server, Job = session.Job, T = session.T }
	end

	-- Чужие поля верхнего уровня (их записал сервер новее этого)
	copyUnknown(data, out, KNOWN, "", strict, issues)
	return out, issues
end

--------------------------------------------------------------------------------
-- Имена и проверки
--------------------------------------------------------------------------------

function PlayerData.StoreNameFor(isStudio: boolean): string
	return if isStudio then DataConfig.StoreName .. DataConfig.StudioSuffix else DataConfig.StoreName
end

function PlayerData.KeyFor(userId: number): string
	return DataConfig.KeyPrefix .. string.format("%d", userId)
end

function PlayerData.Ledger(data: any): (boolean, number)
	local stats = data.Stats
	local earned = if type(stats) == "table" then num(stats.Earned, 0) else 0
	local spent = if type(stats) == "table" then num(stats.Spent, 0) else 0
	local expected = EconomyConfig.StartMoney + earned - spent
	return data.Money == expected, expected
end

return PlayerData
