--!strict
--[[
	FishingLine — леска (Beam от кончика удочки до поплавка) и след кончика при броске;
	FishingFxController зовёт step() каждый кадр, пока поплавок активен (только на клиенте).

	Контракт кончика: Attachment0 лески — Handle.TipAttachment удочки в руке (его CFrame двигает
	FisherRod вместе с изгибом удочки), леска всегда выходит из живого согнутого кончика, и её
	первая опорная точка — вдоль удочки (ось TipAttachment = касательная к согнутой удочке).
	Форма — кривая Безье Beam: CurveSize0 вдоль оси кончика, CurveSize1 против оси LineAttachment
	поплавка (её поворачиваем каждый кадр, в осях мира: поплавок кувыркается и качается).
	Режимы (step mode):
	  "hang"    — замах: поплавок висит на кончике — прямая;
	  "flight"  — полёт (amount — доля полёта): леска выходит вдоль удочки и тянется за
	              поплавком дугой, к воде выпрямляется;
	  "slack"   — ожидание: леска провисает и ложится на воду (SAG длины), чуть «дышит»;
	              «примерка» и нырки (amount = dip 0..1) её натягивают;
	  "bite"    — поклёвка: на каждом рывке (amount = dip) натягивается в струну, между — слабее;
	  "taut"    — борьба: натянута и дрожит струной (VIBRATE studs вбок, VIBRATE_HZ), толщина и
	              цвет пульсируют (белый ↔ оранжевый, amount — сила рывка 0..1);
	  "retract" — сматывается: прямая.
	Вспышки поверх: flash() — рыба сорвалась: на LINE_FLASH с толстая и красная, потом — слабина
	(SLACK × SAG за SLACK_IN с, пока поплавок не начнёт сматываться); hook() — подсечка: на
	HOOK_FLASH с белая, толще, светится.

	След кончика (whip): тонкая светлая лента между TipAttachment и точкой WHIP_BASE studs ниже
	по удочке (Trail) — видна только во время броска: FishingFxController включает его на
	FisherPoses.Timing.Swing до срыва поплавка (тот же миг, что фаза Release FisherAnimController:
	одна и та же формула CastTime + LaunchGuard) и гасит через WHIP_AFTER после.

	Бюджет: ни одного соединения и Instance за кадр; ≤ 6 записей свойств Beam / Attachment за кадр
	на поплавок (ширина и цвет — только когда меняются, кроме «taut»).

	API:
	  FishingLine.new(model, lineAttachment, root, tip, float, color, glow) -> Line
	  FishingLine.step(line, now, mode, from, to, amount)
	  FishingLine.flash(line, now)        FishingLine.hook(line, now)
	  FishingLine.flashing(line, now) -> boolean       -- красная вспышка ещё идёт
	  FishingLine.reset(line)                          -- прямая, обычный вид (рыба в прыжке)
	  FishingLine.whip(tip) -> { Instance }            -- след кончика (уже включён)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("UIConfig"))

local FishingLine = {}

local LINE_FLASH = 0.12 -- рыба сорвалась: красная вспышка, с
local HOOK_FLASH = 0.08 -- подсечка: белая вспышка, с
local SAG = 0.12 -- провис лески в ожидании, доля длины
local SLACK, SLACK_IN = 3, 0.15
local VIBRATE, VIBRATE_HZ = 0.22, 13
local WHIP_BASE = 0.9
local BERRY = UIConfig.Palette.Berry.Bottom
local ORANGE = UIConfig.Palette.Sun.Bottom
local WHITE = Color3.new(1, 1, 1)
local TAU = 2 * math.pi

export type Line = {
	beam: Beam,
	attachment: Attachment,
	root: BasePart,
	tip: number, -- толщина у кончика
	float: number, -- … у поплавка
	color: Color3,
	glow: number,
	flashUntil: number?,
	slackFrom: number?,
	hookUntil: number?,
	look: string, -- что сейчас записано (ширина / цвет): "base" | "flash" | "hook" | "taut"
}

function FishingLine.new(
	model: Model,
	lineAttachment: Attachment,
	root: BasePart,
	tip: number,
	float: number,
	color: Color3,
	glow: number
): Line
	local beam = Instance.new("Beam")
	beam.Name = "Line"
	beam.Attachment1 = lineAttachment
	beam.FaceCamera = true
	beam.Segments = 10
	beam.Width0 = tip
	beam.Width1 = float
	beam.Color = ColorSequence.new(color)
	beam.Transparency = NumberSequence.new(0.15)
	beam.LightEmission = glow
	beam.LightInfluence = 0
	beam.Enabled = false -- пока не найден кончик удочки
	beam.Parent = model
	return {
		beam = beam,
		attachment = lineAttachment,
		root = root,
		tip = tip,
		float = float,
		color = color,
		glow = glow,
		flashUntil = nil,
		slackFrom = nil,
		hookUntil = nil,
		look = "base",
	}
end

function FishingLine.flash(line: Line, now: number)
	line.flashUntil = now + LINE_FLASH
	line.slackFrom = now + LINE_FLASH * 0.5
end

function FishingLine.hook(line: Line, now: number)
	line.hookUntil = now + HOOK_FLASH
end

function FishingLine.flashing(line: Line, now: number): boolean
	local flash = line.flashUntil
	return flash ~= nil and now < flash
end

local function setLook(line: Line, look: string)
	if line.look == look then
		return
	end
	line.look = look
	local beam = line.beam
	if look == "flash" then
		beam.Width0, beam.Width1 = 0.2, 0.2
		beam.Color = ColorSequence.new(BERRY)
		beam.LightEmission = 0.6
	elseif look == "hook" then
		beam.Width0, beam.Width1 = line.tip * 2.2, line.float * 1.6
		beam.Color = ColorSequence.new(WHITE)
		beam.LightEmission = 1
	else
		beam.Width0, beam.Width1 = line.tip, line.float
		beam.Color = ColorSequence.new(line.color)
		beam.LightEmission = line.glow
	end
end

-- Ось LineAttachment поплавка — в осях мира (поплавок кувыркается и качается).
local function aim(line: Line, axis: Vector3)
	local frame = line.root.CFrame
	local x = frame:VectorToObjectSpace(axis)
	local up = frame:VectorToObjectSpace(if math.abs(axis.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis)
	line.attachment.CFrame = CFrame.fromMatrix(Vector3.zero, x, up)
end

local function curve(line: Line, c0: number, c1: number)
	local beam = line.beam
	if beam.CurveSize0 ~= c0 then
		beam.CurveSize0 = c0
	end
	if beam.CurveSize1 ~= c1 then
		beam.CurveSize1 = c1
	end
end

-- Один кадр: from — кончик удочки, to — поплавок (точка привязки лески).
function FishingLine.step(line: Line, now: number, mode: string, from: Vector3, to: Vector3, amount: number)
	local span = to - from
	local length = span.Magnitude
	local flat = Vector3.new(span.X, 0, span.Z)
	local away = if flat.Magnitude > 0.05 then flat.Unit else Vector3.xAxis

	-- вид: вспышки поверх режима
	local flash = line.flashUntil
	if flash and now >= flash then
		line.flashUntil = nil
		flash = nil
	end
	local hook = line.hookUntil
	if hook and now >= hook then
		line.hookUntil = nil
		hook = nil
	end
	if flash then
		setLook(line, "flash")
	elseif hook then
		setLook(line, "hook")
	elseif mode == "taut" then
		line.look = "taut"
		local k = 0.5 + 0.5 * math.sin(now * 10)
		local beam = line.beam
		beam.Width0 = line.tip + 0.04 * k
		beam.Width1 = line.float + 0.08 * k
		beam.Color = ColorSequence.new(line.color:Lerp(ORANGE, 0.2 + 0.6 * k))
		beam.LightEmission = 0.4
	else
		setLook(line, "base")
	end

	-- форма
	local slackFrom = line.slackFrom
	if mode ~= "slack" and mode ~= "bite" and mode ~= "taut" then
		line.slackFrom = nil
		slackFrom = nil
	end
	if slackFrom and now >= slackFrom then
		-- сорвалась: леска ослабла и легла дугой
		local u = math.clamp((now - slackFrom) / SLACK_IN, 0, 1)
		aim(line, away)
		curve(line, 0.15 * length * u, SLACK * SAG * length * (1 - (1 - u) ^ 2))
	elseif mode == "slack" and flat.Magnitude > 0.5 then
		aim(line, away)
		local breathe = 1 + 0.06 * math.sin(now * 2.1)
		curve(line, 0.1 * length, SAG * length * breathe * (1 - 0.85 * math.clamp(amount, 0, 1)))
	elseif mode == "bite" and flat.Magnitude > 0.5 then
		aim(line, away)
		local slack = (1 - math.clamp(amount, 0, 1)) ^ 2
		curve(line, 0.05 * length * slack, 0.6 * SAG * length * slack)
	elseif mode == "taut" then
		-- струна дрожит вбок (поперёк лески, горизонтально)
		aim(line, away:Cross(Vector3.yAxis))
		curve(line, 0, VIBRATE * (0.6 + 0.4 * math.clamp(amount, 0, 1)) * math.sin(TAU * VIBRATE_HZ * now))
	elseif mode == "flight" then
		-- за поплавком дугой: выходит вдоль удочки, к воде выпрямляется
		local u = math.clamp(amount, 0, 1)
		aim(line, away)
		curve(line, 0.3 * length * (1 - u), 0.25 * length * (1 - u) * u * 4)
	else
		curve(line, 0, 0)
	end
end

-- Леска снова прямая и обычная (вспышки и слабина сброшены): рыба в прыжке тянет поплавок.
function FishingLine.reset(line: Line)
	line.flashUntil, line.hookUntil, line.slackFrom = nil, nil, nil
	setLook(line, "base")
	curve(line, 0, 0)
end

-- След кончика при броске: лента от TipAttachment до точки WHIP_BASE ниже по удочке.
function FishingLine.whip(tip: Attachment): { Instance }
	local handle = tip.Parent
	if not handle or not handle:IsA("BasePart") then
		return {}
	end
	local base = Instance.new("Attachment")
	base.Name = "WhipBase"
	base.Position = tip.Position - Vector3.new(WHIP_BASE, 0, 0)
	base.Parent = handle
	local trail = Instance.new("Trail")
	trail.Name = "Whip"
	trail.Attachment0 = tip
	trail.Attachment1 = base
	trail.FaceCamera = true
	trail.Lifetime = 0.14
	trail.MinLength = 0.02
	trail.LightEmission = 0.6
	trail.LightInfluence = 0
	trail.Color = ColorSequence.new(WHITE, Color3.fromRGB(190, 230, 255))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	trail.Parent = handle
	return { trail, base }
end

return FishingLine
