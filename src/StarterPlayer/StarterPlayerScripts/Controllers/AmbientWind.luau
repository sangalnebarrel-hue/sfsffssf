--!strict
--[[
	AmbientWind — один ветер на весь мир (помощник AmbientController, модуль).

	Порыв g(t, pos) — медленные волны силы ветра (0,6…1,4), которые БЕГУТ по миру вдоль
	ветра со скоростью GUST_SPEED: пальмы, флаги и гирлянды качаются сильнее не все разом, а
	волной, которую видно глазом. Тот же порыв у камеры раз в 0,25 с пишется в
	Workspace.GlobalWind (только на клиенте): дым из труб, туман водопада и лепестки, которым
	AmbientWind.Follow включил WindAffectsDrag, сносит по ветру, сильнее в порыв.

	AmbientWind.Direction          -- куда дует (единичный, горизонтальный)
	AmbientWind.Gust(t, pos) -> number   -- 0,6…1,4
	AmbientWind.Sway(t, phase, omega) -> number  -- форма качания −1…1 (основной тон + обертоны)
	AmbientWind.Follow(root)       -- частицы дыма/тумана/лепестков под root следуют ветру
	AmbientWind.Apply(now, at)     -- Workspace.GlobalWind по порыву в точке at
]]

local Workspace = game:GetService("Workspace")

local AmbientWind = {}

local DIRECTION = Vector3.new(7, 0, 3).Unit
local STRENGTH = 7.6 -- studs/с — средний ветер (GlobalWind)
local GUST_SPEED = 26 -- порыв бежит по миру, studs/с
local GUST_SLOW = 2 * math.pi / 11 -- длинная волна порывов, рад/с
local GUST_FAST = 2 * math.pi / 4.3 -- короткая, рад/с

-- Частицы, которые сносит ветром (имя эмиттера → минимальный Drag, чтобы ветер их «держал»).
local FOLLOW: { [string]: number } = {
	Smoke = 0.4,
	Mist = 0.5,
	Petals = 0.3,
	Steam = 0.4,
	Leaves = 0.3,
}

AmbientWind.Direction = DIRECTION
AmbientWind.Strength = STRENGTH

-- Сила ветра (≈ 0,6…1,4) в момент t в точке pos: порыв приходит с наветренной стороны.
function AmbientWind.Gust(t: number, pos: Vector3): number
	local s = t - pos:Dot(DIRECTION) / GUST_SPEED
	local g = 1 + 0.25 * math.sin(GUST_SLOW * s) + 0.15 * math.sin(GUST_FAST * s + 1)
	return math.clamp(g, 0.6, 1.4)
end

-- Форма качания (−1…1): основной тон + обертон (неровно, «живо») + мелкая дрожь.
function AmbientWind.Sway(t: number, phase: number, omega: number): number
	local w = omega * t + phase
	return 0.62 * math.sin(w) + 0.28 * math.sin(2.3 * w + 0.7 * phase) + 0.1 * math.sin(5.3 * w + 2.9 * phase)
end

-- Включает снос ветром у дыма, тумана, лепестков под root (свойства пишутся на клиенте, один
-- раз). Возвращает, скольким эмиттерам.
function AmbientWind.Follow(root: Instance): number
	local count = 0
	for _, d in root:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			local drag = FOLLOW[d.Name]
			if drag then
				d.WindAffectsDrag = true
				if d.Drag < drag then
					d.Drag = drag
				end
				count += 1
			end
		end
	end
	return count
end

function AmbientWind.Apply(now: number, at: Vector3)
	Workspace.GlobalWind = DIRECTION * (STRENGTH * AmbientWind.Gust(now, at))
end

return AmbientWind
