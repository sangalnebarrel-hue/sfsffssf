--!strict
--[[
	AlertLayout — где встаёт тревога хозяина (Этап 4; помощник AlertController — модуль, не
	контроллер; docs/stage4_design.md §6.3, §6.9). Только расчёт прямоугольников в px корня HUD:
	ничего не создаёт и не подключает.

	  • plate(hudSize, column, offset, width, height) — плашка «ВОР В САДКЕ!» вверху колонки
	    уведомлений: по центру, не шире min(width (AlertController: Theft.Width ширины HUD, но не
	    больше Theft.WidthMax), ширины колонки), сверху — верх колонки + offset
	    (NotifyController.Offset("alert"), ниже стопки статуса), высота height.
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
	  • room(r, keepouts, gap, bounds, cap) — запас вокруг стоящей плашки или «таблетки» r, px
	    (0..cap): на сколько она может вырасти влево, вверх, вправо, вниз, пока ни одна помеха не
	    ближе gap и r не выходит за bounds; помеха наискосок (по другой оси ближе cap) ограничивает
	    обе стороны; помеха, что r уже задевает, — только ту сторону, куда она глубже зашла бы
	    (last-mile F-09).
	  • motion(r, room, spec) — как ей выскочить и дрогнуть, не выходя из этого запаса: масштаб
	    растёт от левого верхнего угла (AnchorPoint 0, 0) — перелёт Back (spec.over доли пути от
	    spec.from) только если он влезает справа и снизу, иначе flat (без перелёта); наклон
	    громкой тревоги — не больше spec.tilt° и такой, что поднятый угол (полширины × sin)
	    влезает сверху, а бок (полвысоты × sin) слева (меньше spec.tiltMin° — без наклона); дрожь —
	    по каждой оси не больше spec.shake и запаса с обеих сторон; «пинок» — пик не больше
	    spec.punch и запаса справа и снизу.
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

export type Room = { left: number, up: number, right: number, down: number }

export type MotionSpec = {
	from: number, -- выскакивает с масштаба
	over: number, -- перелёт Back: доля пути from → 1 сверх 1
	tilt: number, -- наклон громкой тревоги, градусы (не больше)
	tiltMin: number, -- меньше — без наклона
	shake: number, -- дрожь, px (не больше)
	punch: number, -- пик «пинка» (не больше)
}

export type Motion = {
	flat: boolean, -- без перелёта
	tilt: number, -- наклон, градусы (≥ 0; 0 — без него)
	shake: Vector2, -- дрожь по осям, px
	punch: number, -- пик «пинка» (1 — без него)
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

function AlertLayout.room(r: Rect, keepouts: { Rect }, gap: number, bounds: Rect, cap: number): Room
	local left, up = r.x0 - bounds.x0, r.y0 - bounds.y0
	local right, down = bounds.x1 - r.x1, bounds.y1 - r.y1
	for _, k in keepouts do
		local x0, y0, x1, y1 = k.x0 - gap, k.y0 - gap, k.x1 + gap, k.y1 + gap
		local apartX = math.max(x0 - r.x1, r.x0 - x1) -- > 0: рядом по горизонтали
		local apartY = math.max(y0 - r.y1, r.y0 - y1)
		if apartX < 0 and apartY < 0 then
			-- уже внахлёст (удочка своего рыбака за плашкой, губа плашки у его волос на ПК): не
			-- заходить глубже — стоит та сторона, чей край r внутри помехи, а сама помеха за ним
			if y0 <= r.y0 and y1 < r.y1 then
				up = 0
			end
			if y0 > r.y0 and y1 >= r.y1 then
				down = 0
			end
			if x0 <= r.x0 and x1 < r.x1 then
				left = 0
			end
			if x0 > r.x0 and x1 >= r.x1 then
				right = 0
			end
		end
		if apartY < cap then
			if x0 >= r.x1 then
				right = math.min(right, x0 - r.x1)
			elseif x1 <= r.x0 then
				left = math.min(left, r.x0 - x1)
			end
		end
		if apartX < cap then
			if y0 >= r.y1 then
				down = math.min(down, y0 - r.y1)
			elseif y1 <= r.y0 then
				up = math.min(up, r.y0 - y1)
			end
		end
	end
	return {
		left = math.clamp(left, 0, cap),
		up = math.clamp(up, 0, cap),
		right = math.clamp(right, 0, cap),
		down = math.clamp(down, 0, cap),
	}
end

function AlertLayout.motion(r: Rect, room: Room, spec: MotionSpec): Motion
	local w, h = math.max(r.x1 - r.x0, 1), math.max(r.y1 - r.y0, 1)
	-- наклон: поднятый угол влезает сверху, сдвинутый бок — слева (масштаб тогда ≤ 1)
	local sine = math.clamp(math.min(room.up / (w / 2), room.left / (h / 2)), 0, 1)
	local tilt = math.min(math.deg(math.asin(sine)), spec.tilt)
	if tilt < spec.tiltMin then
		tilt = 0
	end
	-- перелёт: масштаб от левого верхнего угла до peak (вправо и вниз), и наклон тогда же
	-- перелетает на over своего угла в другую сторону (опускает угол, сдвигает бок)
	local peak = 1 + spec.over * (1 - spec.from)
	local back = math.sin(math.rad(spec.over * tilt))
	local flat = (peak - 1) * w + peak * h / 2 * back > room.right or (peak - 1) * h + peak * w / 2 * back > room.down
	-- «пинок» — масштаб от того же угла
	local grow = math.min(room.right / w, room.down / h)
	return {
		flat = flat,
		tilt = tilt,
		shake = Vector2.new(math.min(spec.shake, room.left, room.right), math.min(spec.shake, room.up, room.down)),
		punch = 1 + math.clamp(grow, 0, spec.punch - 1),
	}
end

return AlertLayout
