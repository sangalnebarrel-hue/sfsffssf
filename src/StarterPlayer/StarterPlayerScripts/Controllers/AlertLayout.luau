--!strict
--[[
	AlertLayout — где встаёт тревога хозяина (Этап 4; помощник AlertController — модуль, не
	контроллер; docs/stage4_design.md §6.3, §6.9). Только расчёт прямоугольников в px корня HUD:
	ничего не создаёт и не подключает.

	  • plate(hudSize, column, offset, height) — плашка «ВОР В САДКЕ!» вверху колонки уведомлений:
	    по центру, не шире min(Theft.Width ширины HUD, Theft.WidthMax, ширины колонки), сверху —
	    верх колонки + offset (NotifyController.Offset("alert")), высота height.
	  • compact(spec) — «таблетка» на телефоне, когда плашка легла бы на своего рыбака
	    (FishingLayout.fisherBox). Прежнее место spec.keep ещё свободно (ни одна помеха не ближе
	    spec.tight) — остаётся там ("keep": «таблетка» не прыгает, когда открылась мини-игра).
	    Иначе — самое ВЕРХНЕЕ свободное место из трёх полос — справа от рыбака (до колонки
	    кнопок), слева от него (от края экрана), колонка уведомлений — и трёх проходов (с запасом
	    spec.gap и не уже spec.min; с запасом spec.tight; уже — до spec.narrow: AlertController
	    укоротит надпись или спрячет её); при равной высоте — проход и полоса раньше: верх экрана
	    под кнопками Roblox свободен и в ожидании, и в поклёвке, и в мини-игре (они внизу), так
	    что место не меняется вместе с рыбалкой. На этой высоте — самая широкая (не шире
	    spec.max; по центру полосы, у левого края, у правого), ни одна помеха spec.keepouts
	    (рыбак, поплавок, плашки статуса, колонка, кнопка прыжка, джойстик, виджеты рыбалки) не
	    ближе запаса прохода (сверху spec.top вниз шагами spec.step до spec.bottom). Места нет и
	    так — шириной min там, где она
	    закрывает помехи меньше всего (рыбака — в FISHER_COST раз дороже), но НИКОГДА не ближе
	    spec.tight к кнопкам Roblox spec.hard (прыжок, джойстик: под ними большие пальцы); и такого
	    места нет — nil ("none": «таблетки» нет, остаётся «ЩИТ!» в колонке). Возвращает
	    прямоугольник и имя места ("keep" | "right" | "left" | "column" | "fallback" | "none").
]]

local FishingLayout = require(script.Parent:WaitForChild("FishingLayout"))

export type Rect = FishingLayout.Rect

export type CompactSpec = {
	fisher: Rect, -- свой рыбак (с запасом FISHER_PAD)
	keepouts: { Rect }, -- всё, до чего держать gap (рыбак — тоже здесь)
	hard: { Rect }?, -- кнопки Roblox (прыжок, джойстик): их не закрывает даже последний выбор
	keep: Rect?, -- где «таблетка» стоит сейчас: свободно — там и остаётся
	top: number, -- не выше
	bottom: number, -- низ не ниже
	left: number, -- край экрана слева (EDGE)
	right: number, -- правый предел (левый край колонки − gap, край экрана)
	column: { x0: number, x1: number }, -- колонка уведомлений по ширине
	height: number,
	min: number,
	max: number,
	gap: number,
	tight: number?, -- второй проход: меньший запас (места с gap нет нигде)
	narrow: number?, -- третий проход: не уже (без надписи)
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

-- Полоса x0..x1: самое верхнее место (сверху вниз шагами step), где встаёт «таблетка» не уже min,
-- и на этой высоте — самая широкая (до max, уже шагами NARROW; по центру полосы, у левого края,
-- у правого), не ближе gap ни к одной помехе.
local NARROW = 20

local function slide(spec: CompactSpec, x0: number, x1: number): Rect?
	local room = x1 - x0
	if room < spec.min then
		return nil
	end
	local widest = math.min(room, spec.max)
	local y = spec.top
	while y + spec.height <= spec.bottom do
		local w = widest
		while true do
			for _, left in { x0 + (room - w) / 2, x0, x1 - w } do
				local r = FishingLayout.rect(left, y, left + w, y + spec.height)
				if clear(r, spec.keepouts, spec.gap) then
					return r
				end
			end
			if w <= spec.min then
				break
			end
			w = math.max(w - NARROW, spec.min)
		end
		y += spec.step
	end
	return nil
end

-- Места нет ни в одной полосе: «таблетка» шириной min там, где она закрывает помехи меньше всего
-- (рыбака — в FISHER_COST раз дороже: он важнее всего).
local FISHER_COST = 20

local function leastCover(spec: CompactSpec, bands: { { number } }): Rect?
	local best: Rect? = nil
	local bestCost = math.huge
	local w = spec.min
	local hard = spec.hard or {}
	local tight = spec.tight or spec.gap
	for _, band in bands do
		local x0, x1 = band[1], math.max(band[2], band[1] + w)
		local y = spec.top
		while y + spec.height <= spec.bottom do
			for _, left in { x0, (x0 + x1 - w) / 2, x1 - w } do
				local r = FishingLayout.rect(left, y, left + w, y + spec.height)
				if clear(r, hard, tight) then
					local cost = FishingLayout.overlapArea(r, spec.fisher) * FISHER_COST
					for _, k in spec.keepouts do
						cost += FishingLayout.overlapArea(r, k)
					end
					if cost < bestCost then
						best, bestCost = r, cost
					end
				end
			end
			y += spec.step
		end
	end
	return best
end

function AlertLayout.compact(spec: CompactSpec): (Rect?, string)
	local tight = spec.tight or spec.gap
	local keep = spec.keep
	if
		keep
		and keep.y0 >= spec.top
		and keep.y1 <= spec.bottom
		and keep.x0 >= spec.left
		and keep.x1 <= spec.right + 0.5
		and clear(keep, spec.keepouts, tight)
	then
		return keep, "keep"
	end
	local fisher = spec.fisher
	local bands = {
		{ fisher.x1 + spec.gap, spec.right },
		{ spec.left, fisher.x0 - spec.gap },
		{ spec.column.x0, spec.column.x1 },
	}
	local names = { "right", "left", "column" }
	-- три прохода: с запасом gap, с tight (ровно 16 px до чужих коробок и обводок), уже — до narrow
	-- (надпись короче или её нет: 🚨 и кнопка); из всех — самое верхнее место (при равной высоте —
	-- проход раньше, полоса раньше): узкая «таблетка» вверху лучше широкой ниже — верх не занимают
	-- ни поклёвка, ни мини-игра, место не прыгает
	local best: Rect?, bestName = nil, ""
	for _, pass in { { spec.gap, spec.min }, { tight, spec.min }, { tight, spec.narrow or spec.min } } do
		local try = table.clone(spec)
		try.gap, try.min = pass[1], pass[2]
		for index, band in bands do
			local r = slide(try, band[1], band[2])
			if r and (best == nil or r.y0 < (best :: Rect).y0 - 0.5) then
				best, bestName = r, names[index]
			end
		end
	end
	if best then
		return best, bestName
	end
	local least = leastCover(spec, { bands[1], bands[2] })
	if least then
		return least, "fallback"
	end
	return nil, "none"
end

return AlertLayout
