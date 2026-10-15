--!strict
--[[
	FishBody — рыба из блоков (Assets.Fish, tools/builder/gear/fish) гнётся, как живая: голова
	жёсткая, тело за «шарниром» изгибается дугой к хвосту. Только математика, без Instance и
	соединений; пользуются FishLife (рыба над головой — через C0 сварок, рыба в прыжке — через
	BulkMoveTo копии) — FishingFxController.

	Оси рыбы — оси её модели (pivot = деталь Body): +X — нос, +Y — спина, Z — бок. Шарнир — на
	HEAD_SHARE длины рыбы от носа; деталь с центром перед ним не гнётся. Изгиб задают два угла
	у кончика хвоста (рад): yaw — вбок (вокруг Y, хвост уходит в +Z), up — вверх-вниз (вокруг
	Z, хвост уходит в +Y); угол касательной «позвоночника» на доле s от шарнира к хвосту — угол·s²
	(дуга «консоль с грузом»), центр детали едет по этой дуге, деталь поворачивается по
	касательной. Углы до ≈0,6 рад — приближение точное до долей stud; блоки слегка расходятся
	и наезжают друг на друга — так читается мультяшный изгиб.

	API:
	  FishBody.new(parts, rest) -> Body     -- rest[i] — деталь parts[i] в осях рыбы в покое
	  FishBody.fromModel(model) -> Body?    -- по нынешнему положению деталей (покой) от pivot модели
	  FishBody.bent(body, i, yaw, up) -> CFrame  -- деталь i в осях рыбы при изгибе
	  FishBody.box(body) -> (CFrame, Vector3)    -- рамка рыбы в её осях (покой): центр и размер
	  FishBody.bends(body, i) -> boolean    -- деталь i за шарниром (её C0 / положение меняется)
]]

local FishBody = {}

local HEAD_SHARE = 0.42 -- голова (доля длины от носа) не гнётся

export type Body = {
	parts: { BasePart },
	rest: { CFrame }, -- в осях рыбы, покой
	spine: { CFrame }, -- деталь относительно своей точки «позвоночника» (покой)
	s: { number }, -- доля от шарнира к кончику хвоста (≤ 0 — перед шарниром)
	hinge: number, -- X шарнира
	length: number, -- от шарнира до кончика хвоста, studs
	center: Vector3, -- центр рамки (покой)
	size: Vector3,
}

function FishBody.new(parts: { BasePart }, rest: { CFrame }): Body
	local x0, y0, z0 = math.huge, math.huge, math.huge
	local x1, y1, z1 = -math.huge, -math.huge, -math.huge
	for i, part in parts do
		local cf = rest[i]
		local half = part.Size / 2
		-- полуразмер повёрнутой детали по осям рыбы
		local ex = math.abs(cf.XVector.X) * half.X + math.abs(cf.YVector.X) * half.Y + math.abs(cf.ZVector.X) * half.Z
		local ey = math.abs(cf.XVector.Y) * half.X + math.abs(cf.YVector.Y) * half.Y + math.abs(cf.ZVector.Y) * half.Z
		local ez = math.abs(cf.XVector.Z) * half.X + math.abs(cf.YVector.Z) * half.Y + math.abs(cf.ZVector.Z) * half.Z
		local p = cf.Position
		x0, y0, z0 = math.min(x0, p.X - ex), math.min(y0, p.Y - ey), math.min(z0, p.Z - ez)
		x1, y1, z1 = math.max(x1, p.X + ex), math.max(y1, p.Y + ey), math.max(z1, p.Z + ez)
	end
	if #parts == 0 then
		x0, y0, z0, x1, y1, z1 = 0, 0, 0, 0, 0, 0
	end
	local lo, hi = Vector3.new(x0, y0, z0), Vector3.new(x1, y1, z1)
	local nose, tail = x1, x0
	local hinge = nose - HEAD_SHARE * (nose - tail)
	local length = math.max(hinge - tail, 0.1)
	local spine, s = {}, {}
	for i, cf in rest do
		local x = cf.Position.X
		s[i] = (hinge - x) / length
		spine[i] = CFrame.new(-x, 0, 0) * cf -- = CFrame.new(0, y, z) * поворот
	end
	return {
		parts = parts,
		rest = rest,
		spine = spine,
		s = s,
		hinge = hinge,
		length = length,
		center = (lo + hi) / 2,
		size = hi - lo,
	}
end

function FishBody.fromModel(model: Model): Body?
	local inverse = model:GetPivot():Inverse()
	local parts: { BasePart } = {}
	local rest: { CFrame } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local part = d :: BasePart
			table.insert(parts, part)
			table.insert(rest, inverse * part.CFrame)
		end
	end
	if #parts == 0 then
		return nil
	end
	return FishBody.new(parts, rest)
end

function FishBody.bends(body: Body, i: number): boolean
	return body.s[i] > 0
end

function FishBody.box(body: Body): (CFrame, Vector3)
	return CFrame.new(body.center), body.size
end

-- Деталь i в осях рыбы при изгибе (yaw — вбок, up — вверх; углы у кончика хвоста, рад).
function FishBody.bent(body: Body, i: number, yaw: number, up: number): CFrame
	local s = body.s[i]
	if s <= 0 or (yaw == 0 and up == 0) then
		return body.rest[i]
	end
	local L = body.length
	local s2 = s * s
	local s3 = s2 * s
	-- ∫cos(a·σ²) ≈ s − a²s⁵/10, ∫sin(a·σ²) ≈ a·s³/3 (от шарнира к хвосту, вдоль −X)
	local x = body.hinge - L * (s - (yaw * yaw + up * up) * s2 * s3 / 10)
	local point = CFrame.new(x, L * up * s3 / 3, L * yaw * s3 / 3)
	return point * CFrame.Angles(0, yaw * s2, 0) * CFrame.Angles(0, 0, -up * s2) * body.spine[i]
end

return FishBody
