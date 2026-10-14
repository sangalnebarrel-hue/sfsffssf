--!strict
--[[
	FisherRig — ядро процедурной анимации рыбака (FisherAnimController): находит суставы
	персонажа и пишет позу поверх обычной анимации Roblox через joint.Transform.

	Как это работает (порядок кадра Roblox: … PreAnimation → Animator пишет Transform всех
	суставов → PreSimulation → суставы применяются пачкой → физика):
	  • писать можно ТОЛЬКО в RunService.PreSimulation: запись в RenderStepped / PreRender
	    Animator перетрёт до применения;
	  • каждый кадр поза считается заново поверх свежей позы Animator'а. Если Animator в этот кадр
	    Transform не переписал (EvaluationThrottled — дальние персонажи; Animator'а нет), берём
	    запомненную базу, а не свою же прошлую запись — иначе поворот накапливался бы;
	  • перестали писать — на следующий кадр Animator сам возвращает обычную позу; если его нет,
	    release() один раз кладёт базу обратно;
	  • Transform не реплицируется: каждый клиент анимирует всех рыбаков рядом сам, у себя.
	Суставы трёх видов: R15 Motor6D, R15 AnimationConstraint (Avatar Joint Upgrade — по умолчанию
	в новых играх: C0/C1 там только для чтения, рамка сустава — Attachment0.CFrame) и R6 Motor6D.
	C0 / C1 / RigAttachment не трогаем никогда (на AJU запись C0 — ошибка, правка RigAttachment
	ломает ретаргетинг). Ищем по имени среди Motor6D и AnimationConstraint в любом месте
	персонажа (на AJU рамки могут лежать под Bone); R15 или R6 — по найденным суставам.
	Нет правого плеча (свой риг) — слоя нет вовсе.

	Позы задаются в пространстве Part0 сустава («торс») относительно позы покоя (руки опущены):
	Transform = C0rot⁻¹ · R · C0rot (FisherPoses — углы). У R6 нет талии, локтей и кистей:
	fold() складывает их в RootJoint и плечи (угол удочки сохраняется), сдвиг таза на R6 не
	применяется (ноги R6 не сгибаются). На R15 опущенный таз компенсируют колени
	(legBend: бедро +θ, колено −2θ, лодыжка +θ — ступни остаются на земле).

	API:
	  FisherRig.CHANNELS                   -- канал → { имя сустава R15, имя R6 (nil — нет) }
	  FisherRig.rot(x, y, z) -> CFrame     -- градусы, YXZ (см. FisherPoses)
	  FisherRig.build(character) -> Rig?   -- nil: нет Humanoid или правого плеча
	  FisherRig.isAlive(rig) -> boolean    -- false: суставы заменили (внешность, смерть) — build заново
	  FisherRig.fold(rig, cf, w, add)      -- R6: свернуть каналы (на месте)
	  FisherRig.legBend(rig, drop) -> θ    -- R15: на сколько согнуть ноги под опущенный таз, рад
	  FisherRig.write(joint, override, weight, additive)
	  FisherRig.release(joint) / FisherRig.releaseAll(rig)
]]

local FisherRig = {}

export type Joint = {
	instance: Instance, -- Motor6D | AnimationConstraint
	rot: CFrame, -- поворот C0 (рамка сустава в Part0)
	inv: CFrame,
	base: CFrame, -- поза Animator'а (последняя, которую он записал)
	written: CFrame?, -- что записали мы в прошлый раз (nil — сустав не ведём)
}

export type Rig = {
	character: Model,
	rigType: string, -- "R15" | "R6"
	joints: { [string]: Joint },
	scale: number, -- рост: HumanoidRootPart.Size.Y / 2 (у стандартного персонажа 1)
	leg: number, -- длина ноги бедро → лодыжка (R15), studs
}

-- канал → { имя сустава R15, имя сустава R6 (nil — канала на R6 нет, его сворачивает fold) }
FisherRig.CHANNELS = {
	Root = { "Root", "RootJoint" },
	Waist = { "Waist", nil },
	Neck = { "Neck", "Neck" },
	RShoulder = { "RightShoulder", "Right Shoulder" },
	RElbow = { "RightElbow", nil },
	RWrist = { "RightWrist", nil },
	LShoulder = { "LeftShoulder", "Left Shoulder" },
	LElbow = { "LeftElbow", nil },
	LWrist = { "LeftWrist", nil },
	RHip = { "RightHip", "Right Hip" },
	LHip = { "LeftHip", "Left Hip" },
	RKnee = { "RightKnee", nil },
	LKnee = { "LeftKnee", nil },
	RAnkle = { "RightAnkle", nil },
	LAnkle = { "LeftAnkle", nil },
} :: { [string]: { string? } }

local RAD = math.pi / 180

function FisherRig.rot(x: number?, y: number?, z: number?): CFrame
	return CFrame.fromEulerAnglesYXZ((x or 0) * RAD, (y or 0) * RAD, (z or 0) * RAD)
end

local function isJoint(instance: Instance): boolean
	return instance:IsA("Motor6D") or instance:IsA("AnimationConstraint")
end

-- Рамки сустава в Part0 и Part1 (C0 / C1; у AnimationConstraint — CFrame его вложений).
local function frames(joint: Instance): (CFrame?, CFrame?)
	if joint:IsA("Motor6D") then
		return joint.C0, joint.C1
	end
	local a0 = (joint :: any).Attachment0 :: Attachment?
	local a1 = (joint :: any).Attachment1 :: Attachment?
	return if a0 then a0.CFrame else nil, if a1 then a1.CFrame else nil
end

-- Длина отрезка между точками двух суставов, лежащими в одной детали (C1 верхнего, C0 нижнего).
local function segment(upper: Instance?, lower: Instance?, fallback: number): number
	if not upper or not lower then
		return fallback
	end
	local _, c1 = frames(upper)
	local c0 = frames(lower)
	if not c1 or not c0 then
		return fallback
	end
	local length = (c0.Position - c1.Position).Magnitude
	return if length > 0.2 then length else fallback
end

function FisherRig.build(character: Model): Rig?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local byName: { [string]: Instance } = {}
	for _, d in character:GetDescendants() do
		if isJoint(d) and byName[d.Name] == nil then
			byName[d.Name] = d
		end
	end
	-- R15 или R6 — по суставам (RigType может отставать от деталей).
	local rigType = if humanoid.RigType == Enum.HumanoidRigType.R15 then "R15" else "R6"
	if byName.RightShoulder and byName.Waist then
		rigType = "R15"
	elseif byName["Right Shoulder"] then
		rigType = "R6"
	end
	local joints: { [string]: Joint } = {}
	for channel, names in FisherRig.CHANNELS do
		local name = if rigType == "R15" then names[1] else names[2]
		local instance = if name then byName[name] else nil
		local c0 = if instance then frames(instance) else nil
		if instance and c0 then
			local rot = c0.Rotation
			joints[channel] = {
				instance = instance,
				rot = rot,
				inv = rot:Inverse(),
				base = CFrame.identity,
				written = nil,
			}
		end
	end
	if not joints.RShoulder then
		return nil -- свой риг: слоя нет (остаётся обычная анимация)
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local scale = if root and root:IsA("BasePart") then math.max(root.Size.Y / 2, 0.3) else 1
	local leg = segment(byName.RightHip, byName.RightKnee, scale) + segment(byName.RightKnee, byName.RightAnkle, scale)
	return { character = character, rigType = rigType, joints = joints, scale = scale, leg = leg }
end

function FisherRig.isAlive(rig: Rig): boolean
	local character = rig.character
	if character.Parent == nil then
		return false
	end
	for _, joint in rig.joints do
		if joint.instance.Parent == nil or not joint.instance:IsDescendantOf(character) then
			return false
		end
	end
	return true
end

-- R6: талия → в RootJoint, локоть и кисть → в плечо (угол удочки тот же), левый локоть — наполовину.
-- cf / w / add — позы, веса и добавки по каналам (меняются на месте).
function FisherRig.fold(rig: Rig, cf: { [string]: CFrame }, w: { [string]: number }, add: { [string]: CFrame })
	if rig.rigType ~= "R6" then
		return
	end
	local root, waist = cf.Root, cf.Waist
	if waist then
		cf.Root = (if root then root.Rotation else CFrame.identity) * waist
		w.Root = math.max(w.Root or 0, w.Waist or 0)
	elseif root then
		cf.Root = root.Rotation
	end
	if add.Waist then
		add.Root = (add.Root or CFrame.identity) * add.Waist
	end
	local shoulder = cf.RShoulder
	if shoulder then
		cf.RShoulder = shoulder * (cf.RElbow or CFrame.identity) * (cf.RWrist or CFrame.identity)
	end
	if add.RElbow or add.RWrist then
		add.RShoulder = (add.RShoulder or CFrame.identity)
			* (add.RElbow or CFrame.identity)
			* (add.RWrist or CFrame.identity)
	end
	local left, leftElbow = cf.LShoulder, cf.LElbow
	if left and leftElbow then
		cf.LShoulder = left * CFrame.identity:Lerp(leftElbow, 0.5)
	end
	local addElbow = add.LElbow
	if addElbow then
		add.LShoulder = (add.LShoulder or CFrame.identity) * CFrame.identity:Lerp(addElbow, 0.5)
	end
end

-- R15: таз опущен на drop studs — на сколько согнуть ноги (бедро +θ, колено −2θ, лодыжка +θ).
function FisherRig.legBend(rig: Rig, drop: number): number
	if rig.rigType ~= "R15" or drop <= 0 or rig.leg <= 0 then
		return 0
	end
	return math.acos(math.clamp(1 - drop / rig.leg, -1, 1))
end

-- Тот же ли это Transform, что мы записали (с допуском: если движок хранит его чуть иначе,
-- точное сравнение приняло бы свою же запись за позу Animator'а и копило бы поворот).
local SAME = 1e-4
local function same(a: CFrame, b: CFrame): boolean
	local ax, ay, az, a00, a01, a02, a10, a11, a12, a20, a21, a22 = a:GetComponents()
	local bx, by, bz, b00, b01, b02, b10, b11, b12, b20, b21, b22 = b:GetComponents()
	return math.abs(ax - bx) < SAME
		and math.abs(ay - by) < SAME
		and math.abs(az - bz) < SAME
		and math.abs(a00 - b00) < SAME
		and math.abs(a01 - b01) < SAME
		and math.abs(a02 - b02) < SAME
		and math.abs(a10 - b10) < SAME
		and math.abs(a11 - b11) < SAME
		and math.abs(a12 - b12) < SAME
		and math.abs(a20 - b20) < SAME
		and math.abs(a21 - b21) < SAME
		and math.abs(a22 - b22) < SAME
end
FisherRig.same = same

-- Один канал, один кадр. override — абсолютная цель в пространстве «торса» (относительно позы
-- покоя), смешивается с позой Animator'а по weight; additive — добавка поверх (тоже «торс»).
function FisherRig.write(joint: Joint, override: CFrame?, weight: number, additive: CFrame?)
	local instance = joint.instance :: any
	local current: CFrame = instance.Transform
	local written = joint.written
	if written == nil or not same(current, written) then
		joint.base = current -- Animator записал свежую позу в этот кадр
	end
	local target = joint.rot * joint.base * joint.inv
	if override and weight > 0 then
		target = target:Lerp(override, math.min(weight, 1))
	end
	if additive then
		target = additive * target
	end
	local out = joint.inv * target * joint.rot
	instance.Transform = out
	joint.written = out
end

-- Канал больше не ведём: Animator перепишет его в следующий кадр; если переписывать некому
-- (Animator'а нет / пропуск кадра), один раз возвращаем его последнюю позу.
function FisherRig.release(joint: Joint)
	local written = joint.written
	if written == nil then
		return
	end
	joint.written = nil
	local instance = joint.instance :: any
	if instance.Parent ~= nil and same(instance.Transform, written) then
		instance.Transform = joint.base
	end
end

function FisherRig.releaseAll(rig: Rig)
	for _, joint in rig.joints do
		FisherRig.release(joint)
	end
end

return FisherRig
