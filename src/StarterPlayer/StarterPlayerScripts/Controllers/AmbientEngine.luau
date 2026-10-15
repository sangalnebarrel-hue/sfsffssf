--!strict
--[[
	AmbientEngine — общий «мотор» живого мира (AmbientController и его помощники AmbientWind,
	AmbientWorld, AmbientWater, AmbientCritters). Модуль, не контроллер.

	Всё, что двигается ради красоты, — «предметы» (Item): флаг, лодка, мельница, облако, стайка
	рыб, чайка, бабочка, пена… Предмет знает, где он (pos, radius), докуда его видно двигающимся
	(range) и как поставить свои детали на момент t (write: дописывает детали и их CFrame в общий
	список кадра, или пишет свойство — прозрачность пены, лампочки гирлянды).

	Каждый кадр — ОДНО соединение RunService.PreRender (перед отрисовкой кадра) на весь мир:
	  • ярус — по тому, насколько быстро предмет бежит ПО ЭКРАНУ: speed (studs/с самой быстрой
	    точки) × пикселей на stud на его расстоянии; нужная частота — чтобы шаг за обновление был
	    не больше STEP_PX пикселя (и не ниже minRate предмета — гирлянды, взмахи крыльев):
	      NEAR — нужно больше 20 Гц: каждый кадр;
	      MID  — 7,5…20 Гц: треть яруса за кадр (≈ 20 раз в секунду каждый), по кругу;
	      FAR  — меньше: восьмая часть за кадр (≈ 7,5 раза в секунду);
	    дальше своего range предмет замирает, где был (флаги — 250 studs, облака — 2500);
	    колесо обозрения в 150 studs крутится медленно — FAR, флаг в 20 studs — NEAR;
	  • только то, что на экране (конус камеры + radius + запас MARGIN), — за спиной ничего не
	    считаем; повернул камеру — предмет догоняет позу в тот же кадр (ближний) или через 2–7;
	  • ярусы пересчитываются не разом, а по REFRESH_SLICE предметов за кадр (весь мир ≈ за
	    0,25 с), новые списки подменяют старые в конце прохода;
	  • бюджет на кадр: не больше Budget деталей + записей свойств (телефон 220, ПК 400) —
	    что не влезло, двигается в следующих кадрах (очередь по кругу, ничего не теряется);
	  • все детали кадра — одним Workspace:BulkMoveTo;
	  • позы считаются от абсолютного времени (os.clock), не накапливаются: пропущенные кадры
	    не сбивают движение;
	  • рядом нечего двигать (нет предметов в ярусах и активных «тикеров») — соединение
	    отключается, мир проверяется таймером раз в IDLE_POLL с; появилось — подключается снова.
	Таймеры (Every) и тикеры (OnFrame) живут на том же соединении: ветер раз в 0,25 с, блики
	на воде раз в 0,5 с, выпрыгнувшая рыба — каждый кадр, пока летит.

	API:
	  AmbientEngine.new(budget: number?) -> Engine
	  engine:Add(item: Item) -> Item          -- предмет мира (см. тип Item)
	  engine:Every(interval, fn(now))         -- таймер на соединении мира
	  engine:OnFrame(fn(now, dt) -> boolean)  -- каждый кадр, пока fn возвращает true
	  engine:OnSleep(fn())                    -- мотор засыпает (рядом пусто): выключить своё
	  engine:Start() / engine:Stop()
	  engine.Stats                             -- счётчики (тесты, превью, замеры)
	  AmbientEngine.Visible(engine, pos, radius) -> boolean  -- на экране ли (по кадру)
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local NEAR = 90 -- nearOnly-предметы (бабочки, стрекозы) — только ближе, studs
local NEAR_HZ = 20 -- нужно чаще — каждый кадр
local MID_HZ = 7.5 -- нужно чаще — MID, иначе FAR
local MID_RATE = 3 -- MID: каждый предмет раз в столько кадров
local FAR_RATE = 8 -- FAR: раз в столько кадров
local STEP_PX = 1.5 -- допустимый шаг на экране за одно обновление, пикселей
local MARGIN = 1.15 -- запас конуса камеры (tan половины угла × MARGIN)
local REFRESH_SLICE = 48 -- столько предметов пересчитываем в ярусы за кадр
local IDLE_POLL = 0.5 -- рядом ничего — проверяем раз в столько секунд, с
local MOVE_MODE = Enum.BulkMoveMode.FireCFrameChanged

export type Item = {
	kind: string, -- вид (для замеров: Stats / Profile)
	pos: Vector3, -- где предмет (подвижные предметы обновляют сами в write)
	radius: number, -- радиус охвата, studs
	speed: number, -- studs/с самой быстрой точки (для яруса)
	minRate: number?, -- обновлять не реже, Гц (бегущий огонь, пена)
	range: number, -- дальше от камеры — не двигается
	cost: number, -- сколько деталей двигает (или свойств пишет) за одно обновление
	write: (item: Item, t: number, engine: Engine) -> (), -- поза на момент t
	-- подвижный предмет: где он в момент t (дёшево; зовётся и для невидимых — иначе ушедший
	-- за край экрана предмет так и остался бы «там» и не вернулся)
	locate: ((item: Item, t: number) -> ())?,
	interval: number?, -- не чаще, чем раз в столько секунд (свойства)
	nearOnly: boolean?, -- только в ближнем ярусе (быстрые взмахи крыльев)
	anchor: Instance?, -- удалили из Workspace — предмет выбывает
	data: any, -- состояние вида предмета
	-- служебное
	last: number,
	dead: boolean,
}

export type Stats = {
	frames: number, -- кадров с работой
	moved: number, -- деталей в последнем кадре
	writes: number, -- записей свойств в последнем кадре
	updated: number, -- предметов обновлено в последнем кадре
	culled: number, -- пропущено (вне экрана) в последнем кадре
	peakMoved: number,
	totalMoved: number,
	totalWrites: number,
	near: number, -- размеры ярусов (после последнего прохода)
	mid: number,
	far: number,
	items: number, -- всего предметов
	connected: boolean,
	idlePolls: number,
}

type Timer = { interval: number, due: number, fn: (now: number) -> () }

export type Engine = {
	items: { Item },
	lists: { { Item } },
	building: { { Item } },
	cursors: { number },
	refreshCursor: number,
	timers: { Timer },
	tickers: { (now: number, dt: number) -> boolean },
	sleepers: { () -> () },
	parts: { BasePart },
	cframes: { CFrame },
	n: number, -- деталей в кадре (write дописывает parts[n], cframes[n])
	w: number, -- записей свойств в кадре
	lastN: number,
	Budget: number,
	Stats: Stats,
	Profile: { [string]: number }?, -- замер: деталей + записей по видам (nil — не считать)
	started: boolean,
	connection: RBXScriptConnection?,
	polling: boolean,
	-- камера кадра
	camPos: Vector3,
	look: Vector3,
	right: Vector3,
	up: Vector3,
	tanX: number,
	tanY: number,
	pxk: number, -- пикселей на stud × расстояние (высота экрана / 2·tan(FOV/2))

	Add: (self: Engine, item: Item) -> Item,
	Every: (self: Engine, interval: number, fn: (now: number) -> ()) -> (),
	OnFrame: (self: Engine, fn: (now: number, dt: number) -> boolean) -> (),
	OnSleep: (self: Engine, fn: () -> ()) -> (),
	Start: (self: Engine) -> (),
	Stop: (self: Engine) -> (),
	Step: (self: Engine, dt: number) -> (),
	RefreshAll: (self: Engine) -> (),
	Push: (self: Engine, part: BasePart, cf: CFrame) -> (),
}

local AmbientEngine = {}

local function readCamera(engine: Engine): boolean
	local camera = Workspace.CurrentCamera
	if not camera then
		return false
	end
	local cf = camera.CFrame
	engine.camPos = cf.Position
	engine.look = cf.LookVector
	engine.right = cf.RightVector
	engine.up = cf.UpVector
	local tan = math.tan(math.rad(camera.FieldOfView) / 2)
	local size = camera.ViewportSize
	local aspect = if size.Y > 1 then size.X / size.Y else 16 / 9
	engine.tanY = tan * MARGIN
	engine.tanX = tan * MARGIN * aspect
	engine.pxk = math.max(size.Y, 200) / (2 * tan)
	return true
end

-- На экране ли шар (pos, radius) — по камере текущего кадра.
local function visible(engine: Engine, pos: Vector3, radius: number): boolean
	local d = pos - engine.camPos
	local z = d:Dot(engine.look)
	if z < -radius then
		return false
	end
	if z <= radius then
		return true -- камера внутри / вплотную
	end
	if math.abs(d:Dot(engine.right)) > z * engine.tanX + radius then
		return false
	end
	return math.abs(d:Dot(engine.up)) <= z * engine.tanY + radius
end
AmbientEngine.Visible = visible

-- Ярус предмета: 0 — замер, 1 NEAR, 2 MID, 3 FAR.
local function classify(item: Item, camPos: Vector3, pxk: number): number
	local d = (item.pos - camPos).Magnitude
	if d > item.range then
		return 0
	end
	if item.nearOnly then
		return if d <= NEAR then 1 else 0
	end
	local hz = item.speed * pxk / (math.max(d - item.radius * 0.5, 1) * STEP_PX)
	local minRate = item.minRate
	if minRate and minRate > hz then
		hz = minRate
	end
	if hz > NEAR_HZ then
		return 1
	elseif hz > MID_HZ then
		return 2
	end
	return 3
end
AmbientEngine.Classify = classify
AmbientEngine.NEAR = NEAR

local function alive(item: Item): boolean
	local anchor = item.anchor
	return anchor == nil or anchor:IsDescendantOf(Workspace)
end

local Engine = {}

function Engine.Add(self: Engine, item: Item): Item
	item.last = -math.huge
	item.dead = false
	table.insert(self.items, item)
	self.Stats.items = #self.items
	return item
end

function Engine.Every(self: Engine, interval: number, fn: (now: number) -> ())
	table.insert(self.timers, { interval = interval, due = 0, fn = fn })
end

function Engine.OnSleep(self: Engine, fn: () -> ())
	table.insert(self.sleepers, fn)
end

function Engine.OnFrame(self: Engine, fn: (now: number, dt: number) -> boolean)
	table.insert(self.tickers, fn)
	if self.started and not self.connection then
		self:Start() -- проснуться ради короткого события
	end
end

function Engine.Push(self: Engine, part: BasePart, cf: CFrame)
	local n = self.n + 1
	self.n = n
	self.parts[n] = part
	self.cframes[n] = cf
end

-- Пересчитать ярусы всех предметов сразу (старт, пробуждение).
function Engine.RefreshAll(self: Engine)
	if not readCamera(self) then
		return
	end
	local lists = self.lists
	for tier = 1, 3 do
		table.clear(lists[tier])
	end
	local camPos = self.camPos
	for _, item in self.items do
		if not item.dead then
			local locate = item.locate
			if locate then
				locate(item, os.clock())
			end
			local tier = classify(item, camPos, self.pxk)
			if tier > 0 then
				table.insert(lists[tier], item)
			end
		end
	end
	for tier = 1, 3 do
		table.clear(self.building[tier])
	end
	self.refreshCursor = 1
	local stats = self.Stats
	stats.near, stats.mid, stats.far = #lists[1], #lists[2], #lists[3]
end

local function hasWork(self: Engine): boolean
	local lists = self.lists
	return #lists[1] + #lists[2] + #lists[3] + #self.tickers > 0
end

-- Конец прохода по ярусам: новые списки вместо старых; убрать удалённые предметы.
local function finishPass(self: Engine)
	self.lists, self.building = self.building, self.lists
	for tier = 1, 3 do
		table.clear(self.building[tier])
	end
	self.refreshCursor = 1
	local items = self.items
	for index = #items, 1, -1 do
		if items[index].dead then
			table.remove(items, index)
		end
	end
	local stats = self.Stats
	stats.items = #items
	stats.near, stats.mid, stats.far = #self.lists[1], #self.lists[2], #self.lists[3]
end

local function refreshSlice(self: Engine)
	local items = self.items
	local total = #items
	if total == 0 then
		return
	end
	local camPos = self.camPos
	local building = self.building
	for _ = 1, math.min(total, REFRESH_SLICE) do
		local index = self.refreshCursor
		if index > total then
			finishPass(self)
			return
		end
		self.refreshCursor = index + 1
		local item = items[index]
		if item.dead then
			continue
		end
		if not alive(item) then
			item.dead = true
			continue
		end
		local locate = item.locate
		if locate then
			locate(item, os.clock())
		end
		local tier = classify(item, camPos, self.pxk)
		if tier > 0 then
			table.insert(building[tier], item)
		end
	end
end

local RATES = { 1, MID_RATE, FAR_RATE }

function Engine.Step(self: Engine, dt: number)
	if not readCamera(self) then
		return
	end
	local now = os.clock()
	self.n = 0
	self.w = 0

	for _, timer in self.timers do
		if now >= timer.due then
			timer.due = now + timer.interval
			timer.fn(now)
		end
	end
	local tickers = self.tickers
	for index = #tickers, 1, -1 do
		if not tickers[index](now, dt) then
			table.remove(tickers, index)
		end
	end

	refreshSlice(self)

	local budget = self.Budget
	local updated, culled = 0, 0
	local lists = self.lists
	for tier = 1, 3 do
		local list = lists[tier]
		local count = #list
		if count == 0 then
			continue
		end
		local quota = if tier == 1 then count else math.ceil(count / RATES[tier])
		local cursor = self.cursors[tier]
		local done = 0
		while done < quota do
			if cursor > count then
				cursor = 1
			end
			local item = list[cursor]
			if not item.dead then
				local interval = item.interval
				if not interval or now - item.last >= interval then
					local locate = item.locate
					if locate then
						locate(item, now)
					end
					if not visible(self, item.pos, item.radius) then
						culled += 1
					else
						-- не влезает в бюджет кадра — первым в следующем кадре (большой предмет
						-- один в пустом кадре проходит всегда)
						local used = self.n + self.w
						if used > 0 and used + item.cost > budget then
							break
						end
						item.last = now
						local profile = self.Profile
						if profile then
							item.write(item, now, self)
							profile[item.kind] = (profile[item.kind] or 0) + self.n + self.w - used
						else
							item.write(item, now, self)
						end
						updated += 1
					end
				end
			end
			cursor += 1
			done += 1
		end
		self.cursors[tier] = cursor
	end

	local n = self.n
	local parts, cframes = self.parts, self.cframes
	for k = n + 1, self.lastN do
		parts[k] = nil
		cframes[k] = nil
	end
	self.lastN = n
	if n > 0 then
		Workspace:BulkMoveTo(parts, cframes, MOVE_MODE)
	end

	local stats = self.Stats
	stats.frames += 1
	stats.moved = n
	stats.writes = self.w
	stats.updated = updated
	stats.culled = culled
	stats.totalMoved += n
	stats.totalWrites += self.w
	if n > stats.peakMoved then
		stats.peakMoved = n
	end

	-- Нечего двигать (конец прохода показал пустые ярусы) — засыпаем до таймера.
	if self.refreshCursor == 1 and not hasWork(self) then
		self:Stop()
		self.started = true
		for _, fn in self.sleepers do
			fn()
		end
		if not self.polling then
			self.polling = true
			task.delay(IDLE_POLL, function()
				self.polling = false
				if self.started and not self.connection then
					self:Start()
				end
			end)
		end
	end
end

function Engine.Start(self: Engine)
	self.started = true
	if self.connection then
		return
	end
	self:RefreshAll()
	if not hasWork(self) then
		self.Stats.idlePolls += 1
		if not self.polling then
			self.polling = true
			task.delay(IDLE_POLL, function()
				self.polling = false
				if self.started and not self.connection then
					self:Start()
				end
			end)
		end
		return
	end
	self.connection = RunService.PreRender:Connect(function(dt: number)
		self:Step(dt)
	end)
	self.Stats.connected = true
end

function Engine.Stop(self: Engine)
	self.started = false
	local connection = self.connection
	if connection then
		connection:Disconnect()
		self.connection = nil
	end
	self.Stats.connected = false
end

function AmbientEngine.new(budget: number?): Engine
	local self = {
		items = {},
		lists = { {}, {}, {} },
		building = { {}, {}, {} },
		cursors = { 1, 1, 1 },
		refreshCursor = 1,
		timers = {},
		tickers = {},
		sleepers = {},
		parts = {},
		cframes = {},
		n = 0,
		w = 0,
		lastN = 0,
		Budget = budget or 400,
		Profile = nil,
		Stats = {
			frames = 0,
			moved = 0,
			writes = 0,
			updated = 0,
			culled = 0,
			peakMoved = 0,
			totalMoved = 0,
			totalWrites = 0,
			near = 0,
			mid = 0,
			far = 0,
			items = 0,
			connected = false,
			idlePolls = 0,
		},
		started = false,
		connection = nil,
		polling = false,
		camPos = Vector3.zero,
		look = Vector3.new(0, 0, -1),
		right = Vector3.new(1, 0, 0),
		up = Vector3.new(0, 1, 0),
		tanX = 1,
		tanY = 1,
		pxk = 300,
	}
	for name, fn in Engine :: any do
		(self :: any)[name] = fn
	end
	return (self :: any) :: Engine
end

return AmbientEngine
