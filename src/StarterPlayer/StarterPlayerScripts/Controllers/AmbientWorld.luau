--!strict
--[[
	AmbientWorld — движение того, что строитель карты ПОМЕТИЛ атрибутами (помощник
	AmbientController, модуль; контракт — tools/builder/DESIGN.md «Ambient attributes»):

	  Spin (°/с)            Model: вращается вокруг оси точки опоры (LookVector); вложенные
	                        Model с KeepUpright = true (кабинки колеса) остаются ровными;
	  Bob (studs), BobPeriod Model: качается на волнах вверх-вниз с лёгким креном;
	  Sway (°), SwayAxis ("X"/"Y"/"Z", ось точки опоры), SwayPeriod (с)
	                        Model или BasePart (детали внутри детали едут с ней): качается
	                        вокруг точки подвеса; сила — по ветру (AmbientWind: порывы бегут по
	                        миру волной), фаза — от положения (ряд флажков гирлянды — волной);
	  Pulse (прозрачность), PulsePeriod (с)
	                        Model: прозрачность каждой детали «дышит» вокруг своей, фаза бежит
	                        вдоль берега (пена прибоя); пишется не чаще 10 раз в секунду;
	  Drift (studs/с)       Model в Map.Sky: медленно плывёт по кругу вокруг центра острова.
	Без атрибутов: гирлянды лампочек (Neon-детали Bulb1, Bulb2 … / ArchBulbs1 … у одного
	родителя) бегут огоньками («бегущий огонь», 6 шагов в секунду, только изменившиеся).
	Вложенные пометки не двигаются (снаружи — главная). Позиции — от исходной позы и времени:
	ошибки не копятся.

	Дальность (range, studs от камеры): Sway 250, Pulse 200, Bob 400, гирлянды 300, Spin 900,
	облака 2500 — видны отовсюду, где можно ходить (ярус FAR, ≈ 7 раз в секунду: на 1200 studs
	шаг меньше пикселя).

	AmbientWorld.Collect(root, engine) -> Summary — пройти root (Workspace.Map или
	Workspace.Bases) и добавить предметы в engine (AmbientEngine). Summary: сколько предметов /
	деталей каждого вида и лодки на воде (bobs) — вокруг них AmbientWater кладёт пену.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AmbientEngine = require(script.Parent:WaitForChild("AmbientEngine"))
local AmbientWind = require(script.Parent:WaitForChild("AmbientWind"))
local MapConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("MapConfig"))

type Engine = AmbientEngine.Engine
type Item = AmbientEngine.Item

local RANGE = {
	Sway = 250,
	Pulse = 200,
	Bob = 400,
	Chase = 300,
	Spin = 900,
	Drift = 2500, -- (облака на r ≈ 1200 видны отовсюду, где можно ходить)
}
local PULSE_RATE = 0.1 -- пена: не чаще, с
local PULSE_CELL = 40 -- пена группами по клеткам столько studs
local PULSE_WAVE = 9 -- длина «бегущей» волны пены вдоль берега: 2π·PULSE_WAVE studs
local CHASE_HZ = 6 -- шагов «бегущего огня» в секунду
local CHASE_DIM = 0.55 -- прозрачность погасшей лампочки
local YIELD_EVERY = 3000 -- обход большой карты — с паузами, чтобы не было рывка кадра

local KINDS = { "Sway", "Bob", "Spin", "Pulse", "Drift" }
local AXES: { [string]: number } = { X = 1, Y = 2, Z = 3 }

export type Bob = {
	model: Model,
	base: CFrame, -- исходная точка опоры
	amplitude: number,
	omega: number,
	phase: number,
	size: Vector3, -- габарит модели (в её осях)
	box: CFrame, -- центр габарита
}

export type Summary = {
	items: { [string]: number },
	parts: { [string]: number },
	bobs: { Bob },
}

local AmbientWorld = {}

-- Детали предмета: сама деталь (если это деталь) и все детали внутри.
local function partsOf(inst: Instance): { BasePart }
	local list: { BasePart } = {}
	if inst:IsA("BasePart") then
		table.insert(list, inst)
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

-- Охват деталей от точки center: радиус шара, в который они все влезают.
local function reach(parts: { BasePart }, center: Vector3): number
	local r = 1
	for _, part in parts do
		r = math.max(r, (part.Position - center).Magnitude + part.Size.Magnitude / 2)
	end
	return r
end

local function centerOf(parts: { BasePart }): Vector3
	local sum = Vector3.zero
	for _, part in parts do
		sum += part.Position
	end
	return if #parts > 0 then sum / #parts else Vector3.zero
end

local function hashPhase(p: Vector3): number
	return (p.X * 0.37 + p.Z * 0.61) % (2 * math.pi)
end

local function pushRigid(engine: Engine, frame: CFrame, parts: { BasePart }, offsets: { CFrame })
	local n = engine.n
	local P, C = engine.parts, engine.cframes
	for k = 1, #parts do
		n += 1
		P[n] = parts[k]
		C[n] = frame * offsets[k]
	end
	engine.n = n
end
AmbientWorld.PushRigid = pushRigid

local function offsetsFrom(base: CFrame, parts: { BasePart }): { CFrame }
	local inverse = base:Inverse()
	local offsets: { CFrame } = {}
	for k, part in parts do
		offsets[k] = inverse * part.CFrame
	end
	return offsets
end

--------------------------------------------------------------------------------------------
-- Виды
--------------------------------------------------------------------------------------------

local function writeSpin(item: Item, t: number, engine: Engine)
	local d = item.data
	local frame = d.base * CFrame.Angles(0, 0, (d.speed * t) % (2 * math.pi))
	pushRigid(engine, frame, d.parts, d.offsets)
	for _, group in d.uprights do
		-- кабинка едет вместе с колесом, но сохраняет свой исходный поворот
		pushRigid(engine, CFrame.new(frame * group.pivot) * group.rotation, group.parts, group.offsets)
	end
end

-- Ближайшая вложенная модель с KeepUpright = true между деталью и вращающейся моделью.
local function uprightAncestor(part: BasePart, root: Model): Model?
	local node = part.Parent
	while node and node ~= root do
		if node:IsA("Model") and node:GetAttribute("KeepUpright") == true then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function makeSpin(model: Model, spin: number): Item
	local base = model:GetPivot()
	local parts: { BasePart } = {}
	local uprights = {}
	local groups: { [Model]: any } = {}
	local all = partsOf(model)
	for _, part in all do
		local holder = uprightAncestor(part, model)
		if holder then
			local group = groups[holder]
			if not group then
				local pivot = holder:GetPivot()
				group = {
					pivot = base:PointToObjectSpace(pivot.Position),
					rotation = pivot.Rotation,
					origin = pivot,
					parts = {},
					offsets = {},
				}
				groups[holder] = group
				table.insert(uprights, group)
			end
			table.insert(group.parts, part)
			table.insert(group.offsets, group.origin:Inverse() * part.CFrame)
		else
			table.insert(parts, part)
		end
	end
	local radius = reach(all, base.Position)
	return {
		pos = base.Position,
		radius = radius,
		speed = math.rad(math.abs(spin)) * radius,
		range = RANGE.Spin,
		cost = #all,
		kind = "Spin",
		write = writeSpin,
		anchor = model,
		data = {
			base = base,
			speed = math.rad(spin),
			parts = parts,
			offsets = offsetsFrom(base, parts),
			uprights = uprights,
		},
	} :: any
end

local function writeBob(item: Item, t: number, engine: Engine)
	local d = item.data
	local w = d.omega * t + d.phase
	local s = math.sin(w)
	local frame = d.base * CFrame.new(0, d.amplitude * s, 0) * CFrame.Angles(0.04 * s, 0, 0.03 * math.cos(w))
	pushRigid(engine, frame, d.parts, d.offsets)
end

local function makeBob(model: Model, amplitude: number): (Item, Bob)
	local period = model:GetAttribute("BobPeriod")
	local base = model:GetPivot()
	local parts = partsOf(model)
	local omega = 2 * math.pi / (if typeof(period) == "number" and period > 0 then period else 3)
	local phase = hashPhase(base.Position) -- своя фаза у каждой лодки, одинаковая у всех игроков
	local box, size = model:GetBoundingBox()
	local radius = reach(parts, base.Position)
	local item = {
		pos = base.Position,
		radius = radius,
		speed = omega * (amplitude + 0.04 * radius),
		range = RANGE.Bob,
		cost = #parts,
		kind = "Bob",
		write = writeBob,
		anchor = model,
		data = {
			base = base,
			amplitude = amplitude,
			omega = omega,
			phase = phase,
			parts = parts,
			offsets = offsetsFrom(base, parts),
		},
	} :: any
	local bob: Bob = {
		model = model,
		base = base,
		amplitude = amplitude,
		omega = omega,
		phase = phase,
		size = size,
		box = box,
	}
	return item, bob
end

local function writeSway(item: Item, t: number, engine: Engine)
	local d = item.data
	local angle = d.amp * AmbientWind.Gust(t, d.at) * AmbientWind.Sway(t, d.phase, d.omega)
	local axis = d.axis
	local rot = if axis == 1
		then CFrame.Angles(angle, 0, 0)
		elseif axis == 2 then CFrame.Angles(0, angle, 0)
		else CFrame.Angles(0, 0, angle)
	pushRigid(engine, d.pivot * rot, d.parts, d.offsets)
end

local function makeSway(inst: PVInstance, amplitude: number): Item?
	local pivot = inst:GetPivot()
	local parts = partsOf(inst)
	if #parts == 0 then
		return nil
	end
	local axisName = inst:GetAttribute("SwayAxis")
	local period = inst:GetAttribute("SwayPeriod")
	local center = centerOf(parts)
	local amp = math.rad(math.clamp(amplitude, 0, 30))
	local omega = 2 * math.pi / (if typeof(period) == "number" and period > 0 then period else 3)
	return {
		pos = center,
		radius = reach(parts, center),
		-- плечо от точки подвеса × угловая скорость × обертоны и порывы (≈ 3)
		speed = amp * omega * reach(parts, pivot.Position) * 3,
		range = RANGE.Sway,
		cost = #parts,
		kind = "Sway",
		write = writeSway,
		anchor = inst,
		data = {
			pivot = pivot,
			at = pivot.Position,
			amp = amp,
			axis = if typeof(axisName) == "string" and AXES[axisName] then AXES[axisName] else 1,
			omega = omega,
			phase = hashPhase(pivot.Position),
			parts = parts,
			offsets = offsetsFrom(pivot, parts),
		},
	} :: any
end

local function writeDrift(item: Item, t: number, engine: Engine)
	local d = item.data
	local frame = CFrame.Angles(0, (d.omega * t) % (2 * math.pi), 0) * d.base
	item.pos = frame.Position
	pushRigid(engine, frame, d.parts, d.offsets)
end

local function makeDrift(model: Model, speed: number): Item?
	local base = model:GetPivot()
	local parts = partsOf(model)
	local flat = Vector3.new(base.Position.X, 0, base.Position.Z).Magnitude
	if #parts == 0 or flat < 1 then
		return nil
	end
	local radius = reach(parts, base.Position)
	return {
		pos = base.Position,
		radius = radius,
		speed = speed + speed / flat * radius,
		range = RANGE.Drift,
		cost = #parts,
		kind = "Drift",
		write = writeDrift,
		locate = function(item: Item, t: number)
			local d = item.data
			item.pos = (CFrame.Angles(0, (d.omega * t) % (2 * math.pi), 0) * d.base).Position
		end,
		anchor = model,
		data = {
			base = base,
			omega = speed / flat, -- studs/с по кругу радиуса flat
			parts = parts,
			offsets = offsetsFrom(base, parts),
		},
	} :: any
end

local function writePulse(item: Item, t: number, engine: Engine)
	local d = item.data
	local parts, base, phase = d.parts, d.base, d.phase
	local amp, omega = d.amp, d.omega
	for k = 1, #parts do
		parts[k].Transparency = math.clamp(base[k] + amp * math.sin(omega * t - phase[k]), 0, 1)
	end
	engine.w += #parts
end

-- Пена: детали Model группами по клеткам PULSE_CELL (один предмет — одна клетка).
local function makePulse(model: Model, amplitude: number): { Item }
	local period = model:GetAttribute("PulsePeriod")
	local omega = 2 * math.pi / (if typeof(period) == "number" and period > 0 then period else 3)
	local cells: { [string]: { BasePart } } = {}
	for _, part in partsOf(model) do
		local p = part.Position
		local key = `{math.floor(p.X / PULSE_CELL)},{math.floor(p.Z / PULSE_CELL)}`
		local cell = cells[key]
		if not cell then
			cell = {}
			cells[key] = cell
		end
		table.insert(cell, part)
	end
	local items = {}
	for _, parts in cells do
		local base, phase = {}, {}
		for k, part in parts do
			local p = part.Position
			base[k] = part.Transparency
			-- фаза бежит вдоль берега (по дуге вокруг центра острова)
			phase[k] = math.atan2(p.X, p.Z) * Vector3.new(p.X, 0, p.Z).Magnitude / PULSE_WAVE
		end
		local center = centerOf(parts)
		table.insert(
			items,
			{
				pos = center,
				radius = reach(parts, center),
				speed = 0, -- (прозрачность: FAR, ≈ 7 раз в секунду — для волны в 3,5 с хватает)
				range = RANGE.Pulse,
				cost = #parts,
				interval = PULSE_RATE,
				kind = "Pulse",
				write = writePulse,
				anchor = model,
				data = { parts = parts, base = base, phase = phase, amp = amplitude, omega = omega },
			} :: any
		)
	end
	return items
end

local function writeChase(item: Item, t: number, engine: Engine)
	local d = item.data
	local step = math.floor(t * CHASE_HZ)
	if step == d.step then
		return
	end
	d.step = step
	local period = d.period
	local half = period / 2
	for i, bulb in d.bulbs do
		local lit = (step - i) % period < half
		if lit ~= d.state[i] then
			d.state[i] = lit
			bulb.Transparency = if lit then d.on[i] else CHASE_DIM
			engine.w += 1
		end
	end
end

-- Гирлянды: Neon-детали с именем «…Bulb<n>» / «…Bulbs<n>» у одного родителя (≥ 2), по номеру.
local function scanBulbs(container: Instance, into: { Item })
	local found: { { part: BasePart, index: number } } = {}
	for _, child in container:GetChildren() do
		if child:IsA("BasePart") and child.Material == Enum.Material.Neon then
			local index = string.match(child.Name, "Bulbs?(%d+)$")
			if index then
				table.insert(found, { part = child, index = tonumber(index) or 0 })
			end
		end
	end
	if #found < 2 then
		return
	end
	table.sort(found, function(a: { part: BasePart, index: number }, b: { part: BasePart, index: number }): boolean
		return a.index < b.index
	end)
	local bulbs, on, state = {}, {}, {}
	for k, entry in found do
		bulbs[k] = entry.part
		on[k] = entry.part.Transparency
		state[k] = true
	end
	local center = centerOf(bulbs)
	table.insert(
		into,
		{
			pos = center,
			radius = reach(bulbs, center),
			speed = 0,
			minRate = 2 * CHASE_HZ + 1, -- не пропускать шаги огней
			range = RANGE.Chase,
			cost = #bulbs,
			interval = 1 / (2 * CHASE_HZ),
			kind = "Chase",
			write = writeChase,
			anchor = container,
			data = { bulbs = bulbs, on = on, state = state, step = -1, period = if #bulbs >= 4 then 4 else 2 },
		} :: any
	)
end

--------------------------------------------------------------------------------------------
-- Обход
--------------------------------------------------------------------------------------------

local function movingKind(inst: Instance): (string?, number)
	for _, kind in KINDS do
		local value = inst:GetAttribute(kind)
		if typeof(value) == "number" and value ~= 0 then
			return kind, value
		end
	end
	return nil, 0
end

-- Лодка на воде (не «струи» водопада): точка опоры у уровня воды, разумный размер.
local function onWater(bob: Bob): boolean
	local y = bob.base.Position.Y
	local footprint = math.max(bob.size.X, bob.size.Z)
	return math.abs(y - MapConfig.WaterTop) < 4 and footprint >= 1 and footprint <= 40
end

function AmbientWorld.Collect(root: Instance, engine: Engine): Summary
	local summary: Summary = { items = {}, parts = {}, bobs = {} }
	local visited = 0
	local function count(kind: string, item: Item)
		summary.items[kind] = (summary.items[kind] or 0) + 1
		summary.parts[kind] = (summary.parts[kind] or 0) + item.cost
		engine:Add(item)
	end
	local function visit(node: Instance)
		visited += 1
		if visited % YIELD_EVERY == 0 then
			task.wait()
		end
		local kind, value = movingKind(node)
		if kind and (node:IsA("Model") or node:IsA("BasePart")) then
			-- гирлянды лампочек внутри качающихся / вращающихся моделей тоже бегут огоньками
			local function bulbsInside()
				local bulbs = {}
				for _, d in node:GetDescendants() do
					if d:IsA("Model") or d:IsA("Folder") then
						scanBulbs(d, bulbs)
					end
				end
				scanBulbs(node, bulbs)
				for _, item in bulbs do
					count("Chase", item)
				end
			end
			if kind == "Sway" then
				local item = makeSway(node :: any, value)
				if item then
					count(kind, item)
				end
				if node:IsA("Model") then
					bulbsInside()
				end
				return
			elseif node:IsA("Model") then
				local model = node :: Model
				if kind == "Spin" then
					count(kind, makeSpin(model, value))
					bulbsInside()
				elseif kind == "Bob" then
					local item, bob = makeBob(model, value)
					count(kind, item)
					if onWater(bob) then
						table.insert(summary.bobs, bob)
					end
				elseif kind == "Drift" then
					local item = makeDrift(model, value)
					if item then
						count(kind, item)
					end
				elseif kind == "Pulse" then
					for _, item in makePulse(model, value) do
						count(kind, item)
					end
				end
				return
			end
		end
		if node:IsA("Model") or node:IsA("Folder") then
			local bulbs = {}
			scanBulbs(node, bulbs)
			for _, item in bulbs do
				count("Chase", item)
			end
		end
		for _, child in node:GetChildren() do
			-- (листовые детали без пометки не обходим: их тысячи)
			if
				not child:IsA("BasePart")
				or child:GetAttribute("Sway") ~= nil
				or child:FindFirstChildWhichIsA("BasePart") ~= nil
			then
				visit(child)
			end
		end
	end
	visit(root)
	return summary
end

return AmbientWorld
