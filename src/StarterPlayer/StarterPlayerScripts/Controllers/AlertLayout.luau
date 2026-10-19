--!strict
--[[
	AlertLayout — где встаёт тревога хозяина (Этап 4; помощник AlertController — модуль, не
	контроллер; docs/stage4_design.md §6.3, §6.9). Только расчёт прямоугольников в px корня HUD:
	ничего не создаёт и не подключает.

	  • plate(hudSize, column, offset, height) — плашка «ВОР В САДКЕ!» вверху колонки уведомлений:
	    по центру, не шире min(Theft.Width ширины HUD, Theft.WidthMax, ширины колонки), сверху —
	    верх колонки + offset (NotifyController.Offset("alert")), высота height.
	  • compact(spec) — «таблетка» на телефоне, когда плашка легла бы на своего рыбака
	    (FishingLayout.fisherBox): первое свободное место из кандидатов по очереди — справа от
	    рыбака (до колонки кнопок), слева от него (от края экрана), вверху колонки уведомлений, —
	    каждое не уже spec.min и не шире spec.max, под плашками статуса (spec.top), и ни одна
	    помеха spec.keepouts (рыбак, колонка, кнопка прыжка, джойстик, виджеты рыбалки) не ближе
	    spec.gap px; на месте тесно — ниже шагами spec.step до spec.bottom. Места нет нигде —
	    справа от рыбака, как есть (он важнее всего: на рыбака «таблетка» не ложится никогда,
	    если справа хоть spec.min px). Возвращает прямоугольник и имя места ("right" | "left" |
	    "column" | "fallback").
]]

local FishingLayout = require(script.Parent:WaitForChild("FishingLayout"))

export type Rect = FishingLayout.Rect

export type CompactSpec = {
	fisher: Rect, -- свой рыбак (с запасом FISHER_PAD)
	keepouts: { Rect }, -- всё, до чего держать gap (рыбак — тоже здесь)
	top: number, -- не выше (низ плашек статуса + gap)
	bottom: number, -- низ не ниже
	left: number, -- край экрана слева (EDGE)
	right: number, -- правый предел (левый край колонки − gap, край экрана)
	column: { x0: number, x1: number }, -- колонка уведомлений по ширине
	height: number,
	min: number,
	max: number,
	gap: number,
	step: number,
}

local AlertLayout = {}

function AlertLayout.plate(hudSize: Vector2, column: Rect, offset: number, width: number, height: number): Rect
	local w = math.min(width, column.x1 - column.x0)
	local x0 = hudSize.X / 2 - w / 2
	local y0 = column.y0 + offset
	return FishingLayout.rect(x0, y0, x0 + w, y0 + height)
end

local function clear(r: Rect, keepouts: { Rect }, gap: number): boolean
	for _, k in keepouts do
		if FishingLayout.hits(r, FishingLayout.rect(k.x0 - gap, k.y0 - gap, k.x1 + gap, k.y1 + gap)) then
			return false
		end
	end
	return true
end

-- Полоса x0..x1: «таблетка» по центру полосы, не шире max; сверху вниз до первого свободного места.
local function slide(spec: CompactSpec, x0: number, x1: number): Rect?
	local room = x1 - x0
	if room < spec.min then
		return nil
	end
	local w = math.min(room, spec.max)
	local left = x0 + (room - w) / 2
	local y = spec.top
	while y + spec.height <= spec.bottom do
		local r = FishingLayout.rect(left, y, left + w, y + spec.height)
		if clear(r, spec.keepouts, spec.gap) then
			return r
		end
		y += spec.step
	end
	return nil
end

function AlertLayout.compact(spec: CompactSpec): (Rect, string)
	local fisher = spec.fisher
	local right = slide(spec, fisher.x1 + spec.gap, spec.right)
	if right then
		return right, "right"
	end
	local left = slide(spec, spec.left, fisher.x0 - spec.gap)
	if left then
		return left, "left"
	end
	local column = slide(spec, spec.column.x0, spec.column.x1)
	if column then
		return column, "column"
	end
	local x0 = math.min(fisher.x1 + spec.gap, spec.right - spec.min)
	local w = math.max(math.min(spec.right - x0, spec.max), spec.min)
	return FishingLayout.rect(x0, spec.top, x0 + w, spec.top + spec.height), "fallback"
end

return AlertLayout
