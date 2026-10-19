--!strict
--[[
	AlertLayout — где встаёт тревога хозяина (Этап 4; помощник AlertController — модуль, не
	контроллер; docs/stage4_design.md §6.3, §6.9). Только расчёт прямоугольников в px корня HUD:
	ничего не создаёт и не подключает.

	  • plate(hudSize, column, offset, height) — плашка «ВОР В САДКЕ!» вверху колонки уведомлений:
	    по центру, не шире min(Theft.Width ширины HUD, Theft.WidthMax, ширины колонки), сверху —
	    верх колонки + offset (NotifyController.Offset("alert")), высота height.
	  • compact(spec) — «таблетка» на телефоне, когда плашка легла бы на своего рыбака
	    (FishingLayout.fisherBox): первое свободное место из полос по очереди — справа от
	    рыбака (до колонки кнопок), слева от него (от края экрана), колонка уведомлений, — не
	    уже spec.min и не шире spec.max, и ни одна помеха spec.keepouts (рыбак, поплавок,
	    плашки статуса, колонка, кнопка прыжка, джойстик, виджеты рыбалки) не ближе spec.gap px:
	    самая широкая, что встаёт где-то в полосе (сверху spec.top вниз шагами spec.step до
	    spec.bottom; по центру полосы, у левого края, у правого); нигде нет — ещё
	    раз с меньшим запасом spec.tight, потом ещё и уже — до spec.narrow (AlertController
	    прячет надпись). Места нет и так — шириной min там, где она закрывает
	    помехи меньше всего (рыбака — в FISHER_COST раз дороже). Возвращает прямоугольник и имя
	    места ("right" | "left" | "column" | "fallback").
]]

local FishingLayout = require(script.Parent:WaitForChild("FishingLayout"))

export type Rect = FishingLayout.Rect

export type CompactSpec = {
	fisher: Rect, -- свой рыбак (с запасом FISHER_PAD)
	keepouts: { Rect }, -- всё, до чего держать gap (рыбак — тоже здесь)
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

-- Полоса x0..x1: самая широкая «таблетка» (до max, потом уже шагами NARROW до min), что где-то
-- в полосе (сверху вниз шагами step; по центру полосы, у левого края, у правого) не ближе gap ни
-- к одной помехе: широкая с надписью ниже лучше узкой повыше.
local NARROW = 20

local function slide(spec: CompactSpec, x0: number, x1: number): Rect?
	local room = x1 - x0
	if room < spec.min then
		return nil
	end
	local w = math.min(room, spec.max)
	while true do
		local y = spec.top
		while y + spec.height <= spec.bottom do
			for _, left in { x0 + (room - w) / 2, x0, x1 - w } do
				local r = FishingLayout.rect(left, y, left + w, y + spec.height)
				if clear(r, spec.keepouts, spec.gap) then
					return r
				end
			end
			y += spec.step
		end
		if w <= spec.min then
			return nil
		end
		w = math.max(w - NARROW, spec.min)
	end
end

-- Места нет ни в одной полосе: «таблетка» шириной min там, где она закрывает помехи меньше всего
-- (рыбака — в FISHER_COST раз дороже: он важнее всего).
local FISHER_COST = 20

local function leastCover(spec: CompactSpec, bands: { { number } }): Rect
	local best: Rect? = nil
	local bestCost = math.huge
	local w = spec.min
	for _, band in bands do
		local x0, x1 = band[1], math.max(band[2], band[1] + w)
		local y = spec.top
		while y + spec.height <= spec.bottom do
			for _, left in { x0, (x0 + x1 - w) / 2, x1 - w } do
				local r = FishingLayout.rect(left, y, left + w, y + spec.height)
				local cost = FishingLayout.overlapArea(r, spec.fisher) * FISHER_COST
				for _, k in spec.keepouts do
					cost += FishingLayout.overlapArea(r, k)
				end
				if cost < bestCost then
					best, bestCost = r, cost
				end
			end
			y += spec.step
		end
	end
	return best or FishingLayout.rect(spec.left, spec.top, spec.left + w, spec.top + spec.height)
end

function AlertLayout.compact(spec: CompactSpec): (Rect, string)
	local fisher = spec.fisher
	local bands = {
		{ fisher.x1 + spec.gap, spec.right },
		{ spec.left, fisher.x0 - spec.gap },
		{ spec.column.x0, spec.column.x1 },
	}
	local names = { "right", "left", "column" }
	-- сначала с запасом gap, потом — с tight (ровно 16 px до чужих коробок и обводок), потом —
	-- уже, до narrow (без надписи: 🚨 и кнопка)
	local tight = spec.tight or spec.gap
	for _, pass in { { spec.gap, spec.min }, { tight, spec.min }, { tight, spec.narrow or spec.min } } do
		local try = table.clone(spec)
		try.gap, try.min = pass[1], pass[2]
		for index, band in bands do
			local r = slide(try, band[1], band[2])
			if r then
				return r, names[index]
			end
		end
	end
	return leastCover(spec, { bands[1], bands[2] }), "fallback"
end

return AlertLayout
