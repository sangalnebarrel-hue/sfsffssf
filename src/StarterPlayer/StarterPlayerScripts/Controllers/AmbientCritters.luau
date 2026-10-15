--!strict
--[[
	AmbientCritters — немного живности (помощник AmbientController, модуль). Маленькие и
	редкие, только на клиенте, без коллизий и теней (DESIGN.md: декоративных людей и зверей
	«на показ» нет — это фон, как рыбки и чайки):

	  • чайки (8): 6 кружат над островом-деревней, 2 — над лагуной перед ближайшим к камере
	    пирсом. Машут (≈ 1,2 с, 2,6 взмаха в секунду: крыло из двух частей, кончик чёрный и
	    отстаёт), потом парят (≈ 2,5 с, крылья чуть вверх), кренятся в повороте. Раз в 30–45 с
	    «пирсовая» чайка проносится низко над водой у самого пирса (ниже 12 studs) и
	    набирает высоту — не во время своей поклёвки / борьбы;
	  • бабочки (6) у клумб: ближайшие к камере клумбы (детали «Bloom…» группами), петляют
	    вокруг, иногда садятся на цветы и медленно складывают крылья; крылья машут 7 раз в
	    секунду — поэтому только в ближнем ярусе (≤ 90 studs), иначе замирают;
	  • стрекозы (3) у ближайшего пирса: зависают над водой у его боков (0,6–1,4 с, дрожат),
	    потом резко перелетают на 4–8 studs (0,15 с). Ближе к кончику пирса, где леска, не летают.
	AmbientCritters.Start(engine, folder, context)
	AmbientCritters.State — для тестов и превью; AmbientCritters.SwoopSoon() — пике на ближайшем тике.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AmbientEngine = require(script.Parent:WaitForChild("AmbientEngine"))
local MapConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("MapConfig"))

type Engine = AmbientEngine.Engine
type Item = AmbientEngine.Item

export type Base = { model: Model, spot: Vector3, cf: CFrame, posts: { Vector3 } }
export type Context = {
	nearestBase: () -> Base?,
	flowers: { Vector3 }, -- клумбы (верх цветов)
	rng: Random,
}

local WATER = MapConfig.WaterTop
local HUB_GULLS, PIER_GULLS = 6, 2
local FLAP_TIME, GLIDE_TIME, FLAP_HZ = 1.2, 2.5, 2.6
local SWOOP_EVERY = { 30, 45 }
local SWOOP_TIME = 3
local BUTTERFLIES = 6
local BUTTERFLY_RANGE = 70 -- клумбы для бабочек — не дальше от камеры
local DRAGONFLIES = 3

local WHITE = Color3.fromRGB(245, 245, 245)
local WING = Color3.fromRGB(225, 228, 235)
local WINGTIP = Color3.fromRGB(55, 58, 66)
local BEAK = Color3.fromRGB(255, 190, 60)
local BUTTERFLY_COLORS = {
	Color3.fromRGB(255, 205, 40),
	Color3.fromRGB(255, 140, 50),
	Color3.fromRGB(255, 120, 180),
	Color3.fromRGB(110, 190, 255),
	Color3.fromRGB(250, 250, 250),
	Color3.fromRGB(180, 130, 255),
}

local AmbientCritters = {}
AmbientCritters.SwoopSoon = function() end -- (до старта — ничего)
AmbientCritters.State = {
	gulls = {} :: { Item },
	butterflies = {} :: { Item },
	dragonflies = {} :: { Item },
	swoops = 0,
	swooping = false,
	swoopStart = 0, -- os.clock() начала последнего пике
}

local function quietPart(folder: Instance, name: string, size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = size
	part.Color = color
	part.Parent = folder
	return part
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function ownBusy(): boolean
	local player = Players.LocalPlayer
	local state = player and player:GetAttribute("FishingState")
	return state == "Bite" or state == "Reeling"
end

local function flatUnit(v: Vector3, fallback: Vector3): Vector3
	local flat = Vector3.new(v.X, 0, v.Z)
	return if flat.Magnitude > 1e-4 then flat.Unit else fallback
end

--------------------------------------------------------------------------------------------
-- Чайки
--------------------------------------------------------------------------------------------

-- Взмах / парение: 1 — машет, 0 — парит (плавно между ними).
local function flapWeight(t: number, seed: number): number
	local cycle = FLAP_TIME + GLIDE_TIME
	local u = (t + seed) % cycle
	if u < FLAP_TIME then
		return smooth(u / 0.25) -- (вход в взмахи)
	end
	return 1 - smooth((u - FLAP_TIME) / 0.4)
end

local function writeGull(item: Item, t: number, engine: Engine)
	local d = item.data
	local pos, heading = d.path(t)
	local before = select(2, d.path(t - 0.3)) :: Vector3
	local turn = math.atan2(before:Cross(heading).Y, before:Dot(heading)) / 0.3 -- рад/с
	local bank = math.clamp(-turn * 2.4, -0.55, 0.55)
	item.pos = pos
	local flap = flapWeight(t, d.seed)
	local pitch = 0
	local swoopStart = d.swoopStart
	if swoopStart then
		local u = (t - swoopStart) / SWOOP_TIME
		if u > 0 and u < 1 then
			pitch = -math.rad(16) * math.sin(2 * math.pi * u) -- клюв вниз в пике, вверх на подъёме
			if u > 0.45 then
				flap = math.max(flap, smooth((u - 0.45) / 0.1)) -- набирает высоту — машет
			else
				flap = math.min(flap, 1 - smooth(u / 0.15)) -- в пике крылья сложены
			end
		end
	end
	local beat = math.sin(2 * math.pi * FLAP_HZ * t + d.seed)
	local inner = flap * math.rad(38) * beat + (1 - flap) * math.rad(8)
	local outer = flap * math.rad(26) * math.sin(2 * math.pi * FLAP_HZ * t + d.seed - 0.7) - (1 - flap) * math.rad(4)
	pitch += (1 - flap) * math.rad(-3)
	local root = CFrame.lookAt(pos, pos + heading) * CFrame.Angles(pitch, 0, bank)
	local P, C = engine.parts, engine.cframes
	local n = engine.n
	local p = d.parts
	n += 1
	P[n] = p.body
	C[n] = root
	n += 1
	P[n] = p.beak
	C[n] = root * CFrame.new(0, 0.05, -1.3)
	n += 1
	P[n] = p.tail
	C[n] = root * CFrame.new(0, 0.1, 1.35) * CFrame.Angles(math.rad(8), 0, 0)
	for side = -1, 1, 2 do
		local shoulder = root * CFrame.new(0.4 * side, 0.2, -0.1) * CFrame.Angles(0, 0, inner * side)
		n += 1
		P[n] = if side < 0 then p.wingL else p.wingR
		C[n] = shoulder * CFrame.new(0.75 * side, 0, 0)
		n += 1
		P[n] = if side < 0 then p.tipL else p.tipR
		C[n] = shoulder
			* CFrame.new(1.5 * side, 0, 0)
			* CFrame.Angles(0, 0, outer * side)
			* CFrame.new(0.6 * side, 0, 0.05)
	end
	engine.n = n
end

local function makeGull(engine: Engine, folder: Instance, rng: Random, path: (number) -> (Vector3, Vector3)): Item
	local parts = {
		body = quietPart(folder, "Gull", Vector3.new(0.85, 0.75, 2.1), WHITE),
		beak = quietPart(folder, "GullBeak", Vector3.new(0.22, 0.22, 0.5), BEAK),
		tail = quietPart(folder, "GullTail", Vector3.new(0.7, 0.14, 0.7), WING),
		wingL = quietPart(folder, "GullWing", Vector3.new(1.5, 0.14, 0.95), WING),
		wingR = quietPart(folder, "GullWing", Vector3.new(1.5, 0.14, 0.95), WING),
		tipL = quietPart(folder, "GullWingtip", Vector3.new(1.2, 0.12, 0.7), WINGTIP),
		tipR = quietPart(folder, "GullWingtip", Vector3.new(1.2, 0.12, 0.7), WINGTIP),
	}
	local start = path(0)
	return engine:Add({
		pos = start,
		radius = 4,
		speed = 14,
		minRate = 16, -- (взмахи 2,6 раза в секунду — не реже 16 Гц)
		range = 600,
		cost = 7,
		kind = "Gull",
		write = writeGull,
		locate = function(item: Item, t: number)
			item.pos = (path(t))
		end,
		data = {
			parts = parts,
			path = path,
			seed = rng:NextNumber(0, 10),
			swoopStart = nil :: number?,
			pier = nil :: number?,
		},
	} :: any)
end

local function startGulls(engine: Engine, folder: Instance, context: Context)
	local rng = context.rng
	local gulls = AmbientCritters.State.gulls
	for _ = 1, HUB_GULLS do
		local radius = rng:NextNumber(40, MapConfig.HubRadius - 20)
		local height = rng:NextNumber(45, 75)
		local speed = rng:NextNumber(10, 16) / radius * (if rng:NextNumber() < 0.5 then -1 else 1)
		local a0 = rng:NextNumber(0, 2 * math.pi)
		local seed = rng:NextNumber(0, 10)
		local function at(t: number): Vector3
			local a = a0 + t * speed
			local r = radius + 14 * math.sin(0.11 * t + seed)
			return Vector3.new(math.sin(a) * r, height + 3 * math.sin(0.7 * t + seed), math.cos(a) * r)
		end
		table.insert(
			gulls,
			makeGull(engine, folder, rng, function(t: number): (Vector3, Vector3)
				local p = at(t)
				return p, flatUnit(at(t + 0.2) - p, Vector3.new(0, 0, -1))
			end)
		)
	end

	-- Над лагуной перед ближайшим пирсом: круг, ближняя к пирсу точка — чуть дальше его кончика.
	local frame = CFrame.new(0, WATER, -MapConfig.BaseRadius)
	local current: Model? = nil
	local swoopAt = os.clock() + rng:NextNumber(12, 20)
	AmbientCritters.SwoopSoon = function() -- (тесты и превью: пике на ближайшем тике)
		swoopAt = 0
	end
	for k = 1, PIER_GULLS do
		local radius = 30 + 6 * (k - 1)
		local height = 27 + 5 * (k - 1)
		local speed = 11 / radius * (if k == 1 then 1 else -1)
		local a0 = rng:NextNumber(0, 2 * math.pi)
		local seed = rng:NextNumber(0, 10)
		local item: Item
		local function at(t: number): Vector3
			local a = a0 + t * speed
			local lz = -(MapConfig.PierLength + 4 + radius) -- центр круга: за кончиком пирса
			local local_ = Vector3.new(math.sin(a) * radius, 0, lz + math.cos(a) * radius)
			local y = height + 2 * math.sin(0.6 * t + seed)
			local d = item and item.data
			if d and d.swoopStart then
				local u = (t - d.swoopStart) / SWOOP_TIME
				if u >= 0 and u <= 1 then
					y -= (height - 12) * math.sin(math.pi * u) ^ 2
				end
			end
			local p = frame:PointToWorldSpace(local_)
			return Vector3.new(p.X, WATER + y, p.Z)
		end
		item = makeGull(engine, folder, rng, function(t: number): (Vector3, Vector3)
			local p = at(t)
			return p, flatUnit(at(t + 0.2) - p, Vector3.new(0, 0, -1))
		end)
		item.data.pier = k
		table.insert(gulls, item)
	end

	engine:Every(0.5, function(now: number)
		local base = context.nearestBase()
		if base and base.model ~= current then
			local hidden = true
			for _, gull in gulls do
				if gull.data.pier and AmbientEngine.Visible(engine, gull.pos, 30) then
					hidden = false
				end
			end
			if current == nil or hidden then
				current = base.model
				frame = CFrame.new(base.cf.Position.X, WATER, base.cf.Position.Z) * base.cf.Rotation
			end
		end
		-- пике: первая «пирсовая» чайка, когда она подлетает к ближней к пирсу точке круга
		local gull = gulls[HUB_GULLS + 1]
		local d = gull and gull.data
		if not d then
			return
		end
		if d.swoopStart and now > d.swoopStart + SWOOP_TIME then
			d.swoopStart = nil
			AmbientCritters.State.swooping = false
		end
		if now >= swoopAt and not d.swoopStart then
			if ownBusy() then
				swoopAt = now + 5
				return
			end
			-- когда чайка ближе всего к кончику пирса (за один круг, не раньше чем через
			-- полпике — чтобы нырок начался с высоты) — середина пике
			local tip = frame:PointToWorldSpace(Vector3.new(0, 0, -MapConfig.PierLength))
			local best, bestDist = now, math.huge
			for k = 0, 76 do
				local t = now + SWOOP_TIME / 2 + k * 0.25
				local p = d.path(t)
				local dist = Vector3.new(p.X - tip.X, 0, p.Z - tip.Z).Magnitude
				if dist < bestDist then
					best, bestDist = t, dist
				end
			end
			d.swoopStart = best - SWOOP_TIME / 2
			AmbientCritters.State.swoopStart = d.swoopStart
			swoopAt = now + rng:NextNumber(SWOOP_EVERY[1], SWOOP_EVERY[2])
			AmbientCritters.State.swoops += 1
			AmbientCritters.State.swooping = true
		end
	end)
end

--------------------------------------------------------------------------------------------
-- Бабочки
--------------------------------------------------------------------------------------------

local function writeButterfly(item: Item, t: number, engine: Engine)
	local d = item.data
	local anchor: Vector3? = d.anchor
	if not anchor then
		return
	end
	local s = d.seed
	local fly = anchor
		+ Vector3.new(
			d.rx * math.sin(0.55 * t + s),
			1.3 + 0.7 * math.sin(0.9 * t + 2 * s) + 0.15 * math.sin(2 * math.pi * 3 * t),
			d.rz * math.sin(0.83 * t + 3 * s)
		)
	-- присела на цветок на 1–2 с раз в 6–10 с
	local cycle = d.cycle
	local u = (t + s * 3) % cycle
	local perch = smooth(u / 0.35) * (1 - smooth((u - d.sit) / 0.35))
	if u > d.sit + 0.35 then
		perch = 0
	end
	local rest = anchor + d.spot
	local pos = fly:Lerp(rest, perch)
	local ahead = anchor
		+ Vector3.new(d.rx * math.sin(0.55 * (t + 0.1) + s), 0, d.rz * math.sin(0.83 * (t + 0.1) + 3 * s))
	local heading = flatUnit(ahead - Vector3.new(fly.X, anchor.Y, fly.Z), Vector3.new(0, 0, -1))
	if perch > 0.5 then
		heading = d.restHeading
	else
		d.restHeading = heading
	end
	item.pos = pos
	local open = (1 - perch) * math.rad(60) * math.sin(2 * math.pi * 7 * t + s)
		+ perch * math.rad(35) * (1 + math.sin(2 * math.pi * t + s))
	local root = CFrame.lookAt(pos, pos + heading)
	local P, C = engine.parts, engine.cframes
	local n = engine.n
	n += 1
	P[n] = d.body
	C[n] = root
	n += 1
	P[n] = d.wingL
	C[n] = root * CFrame.Angles(0, 0, -open) * CFrame.new(-0.3, 0, 0)
	n += 1
	P[n] = d.wingR
	C[n] = root * CFrame.Angles(0, 0, open) * CFrame.new(0.3, 0, 0)
	engine.n = n
end

local function startButterflies(engine: Engine, folder: Instance, context: Context)
	local rng = context.rng
	local flowers = context.flowers
	local list = AmbientCritters.State.butterflies
	for k = 1, BUTTERFLIES do
		local color = BUTTERFLY_COLORS[(k - 1) % #BUTTERFLY_COLORS + 1]
		local data = {
			body = quietPart(folder, "Butterfly", Vector3.new(0.1, 0.1, 0.4), Color3.fromRGB(60, 50, 45)),
			wingL = quietPart(folder, "ButterflyWing", Vector3.new(0.6, 0.04, 0.5), color),
			wingR = quietPart(folder, "ButterflyWing", Vector3.new(0.6, 0.04, 0.5), color),
			anchor = nil :: Vector3?,
			spot = Vector3.new(rng:NextNumber(-1.2, 1.2), 0.25, rng:NextNumber(-1.2, 1.2)),
			rx = rng:NextNumber(3, 6),
			rz = rng:NextNumber(3, 6),
			seed = rng:NextNumber(0, 10),
			cycle = rng:NextNumber(6, 10),
			sit = rng:NextNumber(1, 2),
			restHeading = Vector3.new(0, 0, -1),
		}
		for _, part in { data.body, data.wingL, data.wingR } do
			part.CFrame = CFrame.new(0, -60, 0)
		end
		table.insert(
			list,
			engine:Add({
				pos = Vector3.new(0, -60, 0),
				radius = 7,
				speed = 3,
				range = AmbientEngine.NEAR,
				nearOnly = true,
				cost = 3,
				kind = "Butterfly",
				write = writeButterfly,
				data = data,
			} :: any)
		)
	end
	if #flowers == 0 then
		return
	end
	-- раз в 2 с: бабочки, чьи клумбы далеко от камеры, перелетают к ближним (незаметно)
	engine:Every(2, function()
		local cam = engine.camPos
		local near: { Vector3 } = {}
		for _, flower in flowers do
			if (flower - cam).Magnitude <= BUTTERFLY_RANGE then
				table.insert(near, flower)
			end
		end
		if #near == 0 then
			return
		end
		local used: { [Vector3]: number } = {}
		for _, item in list do
			local anchor = item.data.anchor
			if anchor and (anchor - cam).Magnitude <= BUTTERFLY_RANGE + 15 then
				used[anchor] = (used[anchor] or 0) + 1
			end
		end
		for _, item in list do
			local anchor = item.data.anchor
			if not anchor or (anchor - cam).Magnitude > BUTTERFLY_RANGE + 15 then
				-- клумба с меньшим числом бабочек, лучше вне экрана
				local best, bestScore = nil, math.huge
				for _, flower in near do
					local score = (used[flower] or 0) * 10
						+ (if AmbientEngine.Visible(engine, flower, 2) then 3 else 0)
						+ rng:NextNumber(0, 2)
					if score < bestScore then
						best, bestScore = flower, score
					end
				end
				if best then
					item.data.anchor = best
					item.pos = best
					used[best] = (used[best] or 0) + 1
				end
			end
		end
	end)
end

--------------------------------------------------------------------------------------------
-- Стрекозы
--------------------------------------------------------------------------------------------

local function dragonflyZone(base: Base, rng: Random): Vector3
	local side = if rng:NextNumber() < 0.5 then -1 else 1
	local lx = side * (MapConfig.PierHalfWidth + rng:NextNumber(3, 13))
	local lz = -rng:NextNumber(12, MapConfig.PierLength - 8)
	local p = base.cf:PointToWorldSpace(Vector3.new(lx, 0, lz))
	return Vector3.new(p.X, WATER + rng:NextNumber(1, 4), p.Z)
end

local function writeDragonfly(item: Item, t: number, engine: Engine)
	local d = item.data
	local base: Base? = d.base
	if not base then
		return
	end
	if t >= d.hoverUntil then
		-- перелёт: 4–8 studs в пределах зоны у пирса
		local from = d.pos
		local to = dragonflyZone(base, d.rng)
		local hop = to - from
		if hop.Magnitude > 8 then
			to = from + hop.Unit * d.rng:NextNumber(4, 8)
			to = Vector3.new(to.X, math.clamp(to.Y, WATER + 1, WATER + 4), to.Z)
		end
		local zoneCheck = base.cf:PointToObjectSpace(to)
		if math.abs(zoneCheck.X) < MapConfig.PierHalfWidth + 2 or zoneCheck.Z < -MapConfig.PierLength + 6 then
			to = dragonflyZone(base, d.rng) -- (не над пирсом и не у кончика, где леска)
		end
		d.from, d.to, d.dartAt = from, to, t
		d.hoverUntil = t + 0.15 + d.rng:NextNumber(0.6, 1.4)
		d.heading = flatUnit(to - from, d.heading)
	end
	local u = math.clamp((t - d.dartAt) / 0.15, 0, 1)
	local k = 1 - (1 - u) * (1 - u)
	local pos = d.from:Lerp(d.to, k) + Vector3.new(0, 0.1 * math.sin(2 * math.pi * 2 * t + d.seed), 0)
	d.pos = d.from:Lerp(d.to, k)
	item.pos = pos
	local jitter = math.rad(6) * math.sin(2 * math.pi * 5.3 * t + d.seed)
	local root = CFrame.lookAt(pos, pos + d.heading) * CFrame.Angles(0, jitter, 0)
	local P, C = engine.parts, engine.cframes
	local n = engine.n
	n += 1
	P[n] = d.body
	C[n] = root
	n += 1
	P[n] = d.wingA
	C[n] = root * CFrame.new(0, 0.1, -0.15) * CFrame.Angles(0, 0, math.rad(8) * math.sin(2 * math.pi * 30 * t))
	n += 1
	P[n] = d.wingB
	C[n] = root * CFrame.new(0, 0.1, 0.08) * CFrame.Angles(0, 0, -math.rad(8) * math.sin(2 * math.pi * 30 * t))
	engine.n = n
end

local function startDragonflies(engine: Engine, folder: Instance, context: Context)
	local rng = context.rng
	local list = AmbientCritters.State.dragonflies
	local colors = { Color3.fromRGB(40, 200, 220), Color3.fromRGB(80, 220, 120), Color3.fromRGB(70, 130, 255) }
	for k = 1, DRAGONFLIES do
		local data = {
			body = quietPart(folder, "Dragonfly", Vector3.new(0.14, 0.14, 0.9), colors[k]),
			wingA = quietPart(folder, "DragonflyWing", Vector3.new(1.1, 0.03, 0.22), Color3.fromRGB(235, 245, 255)),
			wingB = quietPart(folder, "DragonflyWing", Vector3.new(1.0, 0.03, 0.2), Color3.fromRGB(235, 245, 255)),
			base = nil :: Base?,
			rng = Random.new(rng:NextInteger(1, 1e6)),
			seed = rng:NextNumber(0, 10),
			pos = Vector3.new(0, -60, 0),
			from = Vector3.new(0, -60, 0),
			to = Vector3.new(0, -60, 0),
			dartAt = 0,
			hoverUntil = 0,
			heading = Vector3.new(0, 0, -1),
		}
		data.wingA.Transparency = 0.45
		data.wingB.Transparency = 0.45
		for _, part in { data.body, data.wingA, data.wingB } do
			part.CFrame = CFrame.new(0, -60, 0)
		end
		table.insert(
			list,
			engine:Add({
				pos = Vector3.new(0, -60, 0),
				radius = 2,
				speed = 30,
				range = AmbientEngine.NEAR,
				nearOnly = true,
				cost = 3,
				kind = "Dragonfly",
				write = writeDragonfly,
				data = data,
			} :: any)
		)
	end
	engine:Every(1, function()
		local base = context.nearestBase()
		if not base then
			return
		end
		for _, item in list do
			local d = item.data
			if d.base ~= base and not AmbientEngine.Visible(engine, item.pos, 2) then
				d.base = base
				local p = dragonflyZone(base, d.rng)
				d.pos, d.from, d.to = p, p, p
				d.hoverUntil = 0
				item.pos = p
			end
		end
	end)
end

function AmbientCritters.Start(engine: Engine, folder: Instance, context: Context)
	startGulls(engine, folder, context)
	startButterflies(engine, folder, context)
	startDragonflies(engine, folder, context)
end

return AmbientCritters
