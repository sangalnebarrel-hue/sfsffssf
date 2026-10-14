--!strict
--[[
	FisherRod — гнущаяся удочка (FisherAnimController), только на клиенте.

	Удочка — Tool с атрибутом RodId: Handle (рукоять) и детали, приваренные к нему Weld'ами
	с явным C0 (tools/builder/Assets.luau); удочка идёт вдоль +X Handle, кончик —
	Handle.TipAttachment (из него выходит леска FishingFxController — Beam.Attachment0).
	Изгиб — дуга «консоль с грузом на конце»: угол касательной на доле s длины θ(s) = A·(2s − s²)
	(A — угол у кончика), детали за рукоятью поворачиваются и сдвигаются по этой дуге (C0 их
	Weld'ов), TipAttachment.CFrame — тоже: леска и поплавок (он летит из живого кончика)
	идут за согнутым кончиком. Плоскость изгиба — к леске (поплавку), иначе вниз по удочке.

	Изгиб A — двумерная пружина (ω₀ = SPRING, затухание DAMPING — ≈6 Гц, 3 видимых качания):
	тянется к нагрузке (load — рыба тянет, FisherAnimController задаёт по состоянию) и получает
	толчок от ускорения кончика (инерция): замах — кончик отстаёт, резкая остановка броска или
	подсечки — хлёст; леска ослабла (поймал / сорвалась) — удочка распрямляется с отскоком.

	Записи только в C0 Weld'ов удочки и CFrame её TipAttachment, у себя на клиенте
	(не реплицируются; у каждого игрока свой изгиб каждой удочки). restore() возвращает всё как
	было — ДО того, как удочка уходит в рюкзак (иначе в следующий раз она достанется согнутой).

	API:
	  FisherRod.attach(tool) -> Rod?         -- nil: не удочка (нет Handle / TipAttachment)
	  FisherRod.step(rod, dt, load, toward)  -- load — угол нагрузки, рад; toward — точка в мире,
	                                         -- куда тянет леска (nil — вниз)
	  FisherRod.bend(rod) -> number          -- текущий изгиб у кончика, рад (0 — прямая)
	  FisherRod.isSettled(rod) -> boolean    -- прямая и не качается (можно отпускать)
	  FisherRod.restore(rod)
]]

local FisherRod = {}

local SPRING = 38 -- собственная частота изгиба, рад/с (≈6 Гц)
local DAMPING = 0.18 -- затухание: после хлёста ≈3 видимых качания
local INERTIA = 0.22 -- сколько ускорение кончика гнёт удочку: при ≈1300 studs/с² (бросок) ≈11°
local MAX_ACCEL = 2500 -- studs/с²: выше — рывок кадра (телепорт, лаг), не движение
local MAX_BEND = 0.6 -- рад, у кончика (≈34°)
local SUBSTEP = 1 / 120
local EPSILON = 0.002 -- рад: изгиб меньше — удочка прямая

type Segment = {
	weld: Weld,
	c0: CFrame, -- исходный C0
	d: number, -- расстояние от рукояти вдоль удочки (X Handle), studs
}

export type Rod = {
	tool: Tool,
	handle: BasePart,
	tip: Attachment,
	tipCFrame: CFrame, -- исходный CFrame кончика
	length: number, -- от рукояти до кончика, studs
	segments: { Segment }, -- по возрастанию d
	by: number, -- изгиб у кончика по Y Handle, рад
	bz: number, -- … по Z Handle
	vy: number,
	vz: number,
	lastTip: Vector3?, -- где был «прямой» кончик в прошлом кадре (для инерции)
	lastVelocity: Vector3?,
	bent: boolean, -- C0 / кончик сейчас изменены
}

function FisherRod.attach(tool: Tool): Rod?
	local handle = tool:FindFirstChild("Handle")
	local tip = handle and handle:FindFirstChild("TipAttachment")
	if not handle or not handle:IsA("BasePart") or not tip or not tip:IsA("Attachment") then
		return nil
	end
	local length = tip.CFrame.Position.X
	if length < 0.5 then
		return nil
	end
	local segments: { Segment } = {}
	for _, d in tool:GetDescendants() do
		if d:IsA("Weld") then
			local weld = d :: Weld
			local c0: CFrame = weld.C0
			if weld.Part0 == handle and weld.Part1 and weld.Part1 ~= handle and c0.Position.X > 0.05 then
				-- (рукоять и катушка — до X = 0 — не гнутся)
				table.insert(segments, { weld = weld, c0 = c0, d = c0.Position.X })
			end
		end
	end
	table.sort(segments, function(a: Segment, b: Segment): boolean
		return a.d < b.d
	end)
	return {
		tool = tool,
		handle = handle,
		tip = tip,
		tipCFrame = tip.CFrame,
		length = length,
		segments = segments,
		by = 0,
		bz = 0,
		vy = 0,
		vz = 0,
		lastTip = nil,
		lastVelocity = nil,
		bent = false,
	}
end

function FisherRod.bend(rod: Rod): number
	return math.sqrt(rod.by * rod.by + rod.bz * rod.bz)
end

function FisherRod.isSettled(rod: Rod): boolean
	return FisherRod.bend(rod) < EPSILON and math.abs(rod.vy) + math.abs(rod.vz) < 0.05
end

function FisherRod.restore(rod: Rod)
	rod.by, rod.bz, rod.vy, rod.vz = 0, 0, 0, 0
	rod.lastTip, rod.lastVelocity = nil, nil
	if not rod.bent then
		return
	end
	rod.bent = false
	for _, segment in rod.segments do
		segment.weld.C0 = segment.c0
	end
	rod.tip.CFrame = rod.tipCFrame
end

-- Дуга изгиба: рамка сечения на расстоянии d вдоль удочки (в пространстве Handle).
-- angle — угол у кончика, axis — ось поворота (X × направление изгиба), u — направление
-- изгиба (перпендикулярно X). x, w — уже пройденные координаты дуги до s0 (интеграл), их
-- возвращаем для следующего сечения.
local function arcFrame(
	length: number,
	angle: number,
	u: Vector3,
	axis: Vector3,
	s0: number,
	x: number,
	w: number,
	s1: number
): (CFrame, number, number)
	-- от s0 до s1 — по средней точке шагами не больше 0.1 длины
	local steps = math.max(1, math.ceil((s1 - s0) / 0.1))
	local h = (s1 - s0) / steps
	for i = 1, steps do
		local m = s0 + (i - 0.5) * h
		local theta = angle * (2 * m - m * m)
		x += math.cos(theta) * h * length
		w += math.sin(theta) * h * length
	end
	local theta = angle * (2 * s1 - s1 * s1)
	local frame = CFrame.new(Vector3.xAxis * x + u * w) * CFrame.fromAxisAngle(axis, theta)
	return frame, x, w
end

local function apply(rod: Rod)
	local angle = FisherRod.bend(rod)
	if angle < EPSILON then
		if rod.bent then
			rod.bent = false
			for _, segment in rod.segments do
				segment.weld.C0 = segment.c0
			end
			rod.tip.CFrame = rod.tipCFrame
		end
		return
	end
	rod.bent = true
	local u = Vector3.new(0, rod.by / angle, rod.bz / angle)
	local axis = Vector3.xAxis:Cross(u)
	local length = rod.length
	local s, x, w = 0, 0, 0
	for _, segment in rod.segments do
		local s1 = math.min(segment.d / length, 1)
		local frame
		frame, x, w = arcFrame(length, angle, u, axis, s, x, w, s1)
		s = s1
		segment.weld.C0 = frame * CFrame.new(-segment.d, 0, 0) * segment.c0
	end
	local tipFrame = arcFrame(length, angle, u, axis, s, x, w, 1)
	rod.tip.CFrame = tipFrame * CFrame.new(-length, 0, 0) * rod.tipCFrame
end

-- Один кадр: пружина к нагрузке + инерция кончика; пишет C0 и кончик.
function FisherRod.step(rod: Rod, dt: number, load: number, toward: Vector3?)
	if dt <= 0 then
		return
	end
	local handleCFrame = rod.handle.CFrame
	-- Нагрузка: к леске, в плоскости поперёк удочки (иначе — вниз по Y Handle).
	local ty, tz = -load, 0
	if toward and load ~= 0 then
		local tipWorld = handleCFrame:PointToWorldSpace(Vector3.new(rod.length, 0, 0))
		local direction = handleCFrame:VectorToObjectSpace(toward - tipWorld)
		local across = Vector3.new(0, direction.Y, direction.Z)
		if across.Magnitude > 1e-3 then
			across = across.Unit
			ty, tz = across.Y * load, across.Z * load
		end
	end
	-- Инерция: ускорение «прямого» кончика поперёк удочки гнёт её в обратную сторону.
	local tipNow = handleCFrame:PointToWorldSpace(Vector3.new(rod.length, 0, 0))
	local ay, az = 0, 0
	local last = rod.lastTip
	if last then
		local velocity = (tipNow - last) / dt
		local lastVelocity = rod.lastVelocity
		if lastVelocity and velocity.Magnitude < MAX_ACCEL * 0.1 then
			local accel = (velocity - lastVelocity) / dt
			if accel.Magnitude < MAX_ACCEL then
				local local_ = handleCFrame:VectorToObjectSpace(accel)
				ay, az = local_.Y, local_.Z
			end
			rod.lastVelocity = velocity
		else
			rod.lastVelocity = if velocity.Magnitude < MAX_ACCEL * 0.1 then velocity else nil
		end
	end
	rod.lastTip = tipNow
	local k = SPRING * SPRING
	local c = 2 * DAMPING * SPRING
	local remaining = math.min(dt, 0.1)
	while remaining > 1e-6 do
		local h = math.min(SUBSTEP, remaining)
		remaining -= h
		local fy = k * (ty - rod.by) - c * rod.vy - INERTIA * ay
		local fz = k * (tz - rod.bz) - c * rod.vz - INERTIA * az
		rod.vy += fy * h
		rod.vz += fz * h
		rod.by += rod.vy * h
		rod.bz += rod.vz * h
	end
	local angle = FisherRod.bend(rod)
	if angle > MAX_BEND then
		rod.by *= MAX_BEND / angle
		rod.bz *= MAX_BEND / angle
	end
	apply(rod)
end

return FisherRod
