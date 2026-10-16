--!strict
--[[
	FishingLayout — где на экране встают виджеты рыбалки (HUD.Fishing), чтобы не закрывать своего
	рыбака и свой поплавок (v3: анимация рыбака должна быть видна на телефоне — заброс, борьба с
	согнутой удочкой, руки вверх с рыбой над головой). Только расчёт прямоугольников в пикселях
	корня HUD.Fishing; сами виджеты двигает FishingController (вынесено сюда — у контроллера мало
	свободных регистров, см. tests/compile_limits).

	  • fisherBox — прямоугольник своего персонажа на экране: все видимые детали персонажа (тело,
	    удочка, рыба над головой HeldFish, шапки), по 8 углов каждой, с запасом FISHER_PAD px.
	    nil — персонажа нет, он за камерой или дальше MAX_DEPTH studs (камера не за ним).
	  • fallbackFisher — где стоит рыбак у камеры Roblox по умолчанию (она держит персонажа по
	    середине экрана): на телефоне, если спроецировать его не вышло.
	  • bobberBox — свой поплавок на экране: от антенны до нырка на dive studs вниз, с запасом.
	  • avoid — виджет не закрывает ни один прямоугольник keepouts: сначала становится ниже (низ на
	    месте, не меньше minScale), иначе отъезжает вбок в самый широкий свободный просвет span
	    (не уже minWidth, ближе к месту); места нет — как был.
	  • dockSide / dockLeft — слот СБОКУ от рыбака (короткий экран: мини-игра — слева, карточка
	    улова — где шире): от края до рыбака, по высоте — напротив его середины, между top и
	    bottom.
	  • cardDock — карточка улова сбоку от рыбака с трофеем на любом экране, где сбоку хватает
	    места (из нескольких свободных полос — где она крупнее).
	  • leastCover — сбоку не помещается (огромный трофей на маленьком телефоне): место в полосах,
	    где карточка закрывает рыбака с трофеем меньше всего (overlapArea — площадь пересечения).
	  • topBand — полоса НАД рыбаком (и рыбой над головой): огромное слово редкости.
	  • flightHits — заденет ли виджет прямоугольник, вылетая из точки на своё место.
	  • hintWidth — ширина плитки подсказки под её текст.
	  • rectOf / placeOf — прямоугольник виджета «в покое» по Position/Size/AnchorPoint и обратно.
	Ничего не создаёт и не подключает: вызывается в событиях (поклёвка, мини-игра, подсказка,
	карточка), не каждый кадр.
]]

local FishingLayout = {}

export type Rect = { x0: number, y0: number, x1: number, y1: number }

local EDGE = 16 -- до края экрана, px
FishingLayout.EDGE = EDGE
local FISHER_PAD = 12 -- запас вокруг своего рыбака, px
FishingLayout.FISHER_PAD = FISHER_PAD
local MAX_DEPTH = 60 -- рыбак дальше от камеры — камера не за ним (виджеты как обычно), studs
local MAX_PARTS = 240 -- больше деталей не смотрим (рыба над головой — до ~60)

function FishingLayout.rect(x0: number, y0: number, x1: number, y1: number): Rect
	return { x0 = x0, y0 = y0, x1 = x1, y1 = y1 }
end

local function hits(a: Rect, b: Rect): boolean
	return a.x0 < b.x1 and b.x0 < a.x1 and a.y0 < b.y1 and b.y0 < a.y1
end
FishingLayout.hits = hits

-- Точка мира на экране в px корня (origin — его AbsolutePosition) и глубина; nil — за камерой.
local function project(camera: Camera, origin: Vector2, world: Vector3): (Vector2?, number)
	local point = camera:WorldToScreenPoint(world)
	if point.Z <= 0.05 then
		return nil, point.Z
	end
	return Vector2.new(point.X, point.Y) - origin, point.Z
end

--[[
	Свой персонаж на экране (px корня origin), с запасом pad (по умолчанию FISHER_PAD): тело,
	удочка, рыба над головой, шапки — всё, что видно (Transparency < 0.95). nil — нет персонажа
	или камеры, хоть один угол за камерой, или рыбак дальше MAX_DEPTH studs.
]]
function FishingLayout.fisherBox(character: Model?, camera: Camera?, origin: Vector2, pad: number?): Rect?
	if not character or not camera then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local _, depth = project(camera, origin, root.Position)
	if depth <= 0.05 or depth > MAX_DEPTH then
		return nil
	end
	local box: Rect = { x0 = math.huge, y0 = math.huge, x1 = -math.huge, y1 = -math.huge }
	local seen = 0
	for _, item in character:GetDescendants() do
		if seen >= MAX_PARTS then
			break
		end
		if item:IsA("BasePart") and item.Transparency < 0.95 then
			seen += 1
			local cf, half = item.CFrame, item.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local p = project(camera, origin, cf:PointToWorldSpace(half * Vector3.new(sx, sy, sz)))
						if not p then
							return nil
						end
						box.x0, box.y0 = math.min(box.x0, p.X), math.min(box.y0, p.Y)
						box.x1, box.y1 = math.max(box.x1, p.X), math.max(box.y1, p.Y)
					end
				end
			end
		end
	end
	if seen == 0 then
		return nil
	end
	local d: number = pad or FISHER_PAD
	box.x0 -= d
	box.y0 -= d
	box.x1 += d
	box.y1 += d
	return box
end

--[[
	Рыбак у камеры Roblox по умолчанию (12.5 studs, персонаж по середине экрана; так он стоит и в
	превью): по ширине ±0.14 высоты корня от середины, по высоте 0.18…0.72 корня, с запасом
	FISHER_PAD. Для телефона, когда спроецировать персонажа не вышло (нет камеры, тесты).
]]
function FishingLayout.fallbackFisher(rootSize: Vector2): Rect
	local mid, h = rootSize.X / 2, rootSize.Y
	return {
		x0 = mid - 0.14 * h - FISHER_PAD,
		y0 = 0.18 * h - FISHER_PAD,
		x1 = mid + 0.14 * h + FISHER_PAD,
		y1 = 0.72 * h + FISHER_PAD,
	}
end

-- Свой поплавок на экране: от антенны (pivot + 1 stud) до нырка на dive studs вниз, по ширине
-- ±1 stud, с запасом clear px. nil — его нет или он за камерой.
function FishingLayout.bobberBox(bobber: Model?, camera: Camera?, origin: Vector2, dive: number, clear: number): Rect?
	if not bobber or not camera then
		return nil
	end
	local pivot = bobber:GetPivot().Position
	local center = project(camera, origin, pivot)
	local side = project(camera, origin, pivot + camera.CFrame.RightVector)
	local top = project(camera, origin, pivot + Vector3.new(0, 1, 0))
	local bottom = project(camera, origin, pivot - Vector3.new(0, dive, 0))
	if not center or not side or not top or not bottom then
		return nil
	end
	local half = (side - center).Magnitude + clear
	return {
		x0 = center.X - half,
		x1 = center.X + half,
		y0 = math.min(top.Y, bottom.Y) - clear,
		y1 = math.max(top.Y, bottom.Y) + clear,
	}
end

--[[
	Виджет box (px корня) не закрывает ни один прямоугольник keepouts:
	  1) ниже: верх опускается под самый низкий из задетых (низ на месте, ширина — в той же
	     пропорции, по центру), если выходит не меньше minScale и ничего другого не задевает;
	  2) вбок: в самый широкий свободный просвет между span[1] и span[2] (с учётом всех keepouts
	     в полосе виджета), не уже minWidth (и не шире самого виджета), ближе к его месту.
	Иначе — как был. Возвращает новый прямоугольник.
]]
function FishingLayout.avoid(box: Rect, keepouts: { Rect }, span: { number }, minScale: number, minWidth: number): Rect
	local hit = false
	local lowest = -math.huge
	for _, k in keepouts do
		if hits(box, k) then
			hit = true
			lowest = math.max(lowest, k.y1)
		end
	end
	if not hit then
		return box
	end
	local w, h = box.x1 - box.x0, box.y1 - box.y0
	local cx = (box.x0 + box.x1) / 2
	local k = (box.y1 - lowest) / math.max(h, 1)
	if k >= minScale and k > 0 then
		local lower = { x0 = cx - w * k / 2, y0 = box.y1 - h * k, x1 = cx + w * k / 2, y1 = box.y1 }
		local clear = true
		for _, other in keepouts do
			if hits(lower, other) then
				clear = false
			end
		end
		if clear then
			return lower
		end
	end
	-- Свободные просветы по X в полосе виджета: span минус задевающие его по высоте keepouts.
	local blocks: { { number } } = {}
	for _, other in keepouts do
		if other.y0 < box.y1 and box.y0 < other.y1 then
			table.insert(blocks, { other.x0, other.x1 })
		end
	end
	table.sort(blocks, function(a: { number }, b: { number }): boolean
		return a[1] < b[1]
	end)
	local gaps: { { number } } = {}
	local from = span[1]
	for _, b in blocks do
		if b[1] > from then
			table.insert(gaps, { from, math.min(b[1], span[2]) })
		end
		from = math.max(from, b[2])
	end
	if from < span[2] then
		table.insert(gaps, { from, span[2] })
	end
	local bestWidth, bestCenter = 0, cx
	for _, gap in gaps do
		if gap[2] - gap[1] <= 0 then
			continue
		end
		local width = math.min(w, gap[2] - gap[1])
		local middle = math.clamp(cx, gap[1] + width / 2, math.max(gap[1] + width / 2, gap[2] - width / 2))
		local better = width > bestWidth or (width == bestWidth and math.abs(middle - cx) < math.abs(bestCenter - cx))
		if width >= math.min(minWidth, w) and better then
			bestWidth, bestCenter = width, middle
		end
	end
	if bestWidth <= 0 then
		return box
	end
	return { x0 = bestCenter - bestWidth / 2, y0 = box.y0, x1 = bestCenter + bestWidth / 2, y1 = box.y1 }
end

--[[
	Слот сбоку от рыбака fisher (с его запасом): side = -1 — слева, от edge (по умолчанию EDGE)
	до fisher.x0; side = 1 — справа, от fisher.x1 до edge. Ширина до want.X (не уже minWidth —
	иначе nil), высота want.Y; aspect (ширина / высота) — высота следует за шириной. По высоте —
	напротив середины рыбака, но между top и bottom (полоса свободна от плашек статуса,
	джойстика, кнопок); не помещается — nil. По ширине слот — посередине между краем и рыбаком.
]]
function FishingLayout.dockSide(
	side: number,
	fisher: Rect,
	want: Vector2,
	minWidth: number,
	top: number,
	bottom: number,
	aspect: number?,
	edge: number?
): Rect?
	local from = if side < 0 then (edge or EDGE) else fisher.x1
	local to = if side < 0 then fisher.x0 else (edge or 0)
	local w = math.min(want.X, to - from)
	if w < minWidth then
		return nil
	end
	local h = want.Y
	if aspect then
		h = math.min(h, w / aspect, bottom - top)
		w = h * aspect
		if w < minWidth then
			return nil
		end
	elseif bottom - top < h then
		return nil
	end
	-- (Слот ровно во всю полосу: top + h/2 и bottom − h/2 могут разойтись на погрешность float —
	-- math.clamp не терпит max < min.)
	local lo = top + h / 2
	local cy = math.clamp((fisher.y0 + fisher.y1) / 2, lo, math.max(lo, bottom - h / 2))
	local x0 = from + (to - from - w) / 2
	return { x0 = x0, y0 = cy - h / 2, x1 = x0 + w, y1 = cy + h / 2 }
end

-- Слот слева от рыбака (мини-игра на телефоне — без пропорции; поклёвка — с пропорцией aspect:
-- уже — значит и ниже): dockSide(-1, …).
function FishingLayout.dockLeft(
	fisher: Rect,
	want: Vector2,
	minWidth: number,
	top: number,
	bottom: number,
	aspect: number?
): Rect?
	return FishingLayout.dockSide(-1, fisher, want, minWidth, top, bottom, aspect)
end

--[[
	Полоса над рыбаком (и рыбой над головой) для огромного слова: центр и высота (px корня).
	Хотим центр wantY и высоту wantH; низ слова — не ниже fisher.y0 (у него уже есть запас), верх —
	не выше top. Места меньше minH — nil (слово — как раньше).
]]
function FishingLayout.topBand(
	fisher: Rect?,
	wantY: number,
	wantH: number,
	top: number,
	minH: number
): (number?, number?)
	local limit = if fisher then fisher.y0 else math.huge
	local h = math.min(wantH, limit - top)
	if h < minH then
		return nil, nil
	end
	local cy = math.clamp(wantY, top + h / 2, math.max(top + h / 2, limit - h / 2))
	return cy, h
end

--[[
	Заденет ли виджет keepout, вылетая по прямой из точки from на своё место to (в начале — в
	startScale раз меньше, растёт по пути): проверка по шести точкам пути. «КЛЮЁТ!» вылетает из
	поплавка, только если по пути не закрывает своего рыбака.
]]
function FishingLayout.flightHits(from: Vector2, to: Rect, keepout: Rect, startScale: number): boolean
	local cx, cy = (to.x0 + to.x1) / 2, (to.y0 + to.y1) / 2
	local w, h = to.x1 - to.x0, to.y1 - to.y0
	for i = 0, 5 do
		local k = i / 5
		local s = startScale + (1 - startScale) * k
		local x, y = from.X + (cx - from.X) * k, from.Y + (cy - from.Y) * k
		if hits(FishingLayout.rect(x - w * s / 2, y - h * s / 2, x + w * s / 2, y + h * s / 2), keepout) then
			return true
		end
	end
	return false
end

--[[
	Ширина плитки подсказки под её текст (UIM-03): плитка не шире нужного (а не полоса на полэкрана
	над ногами рыбака). Надпись занимает 0.8 ширины справа, значок в кружке — левый край (его
	правый край ≈ 0.78 высоты плитки: плитка не уже 5 высот, иначе надпись наедет на значок).
	Ширина текста — оценка: HINT_CHAR × размер на букву (Nunito Heavy ≈ 0.43, с запасом); не
	влезает в maxWidth — две строки (TextWrapped).
]]
local HINT_CHAR = 0.5
function FishingLayout.hintWidth(text: string, textSize: number, height: number, maxWidth: number): number
	local letters = utf8.len(text) or #text
	local want = (letters * HINT_CHAR * textSize + 8) / 0.8
	return math.floor(math.min(math.max(want, 5 * height), math.max(maxWidth, 5 * height)))
end

-- Прямоугольник (px корня rootSize) элемента с такими Position, размером в px и AnchorPoint.
function FishingLayout.rectOf(position: UDim2, size: Vector2, anchor: Vector2, rootSize: Vector2): Rect
	local x = position.X.Scale * rootSize.X + position.X.Offset - anchor.X * size.X
	local y = position.Y.Scale * rootSize.Y + position.Y.Offset - anchor.Y * size.Y
	return { x0 = x, y0 = y, x1 = x + size.X, y1 = y + size.Y }
end

-- Обратно: Position и Size (целые px) элемента с AnchorPoint anchor, чтобы он занял rect.
function FishingLayout.placeOf(rect: Rect, anchor: Vector2): (UDim2, UDim2)
	local w, h = rect.x1 - rect.x0, rect.y1 - rect.y0
	return UDim2.fromOffset(math.round(rect.x0 + anchor.X * w), math.round(rect.y0 + anchor.Y * h)),
		UDim2.fromOffset(math.round(w), math.round(h))
end

-- Свободная полоса сбоку от рыбака для карточки улова (cardDock): сторона (−1 слева, 1 справа),
-- верх и низ полосы и её края по X (от края экрана, джойстика, кнопок — их считает контроллер).
export type DockBand = { side: number, top: number, bottom: number, left: number, right: number }

--[[
	Карточка улова СБОКУ от рыбака с трофеем над головой (UI v5, D1: и на планшете и компьютере,
	не только на телефоне): keepout — рыбак вместе с трофеем (с запасом), bands — свободные
	полосы рядом с ним (у каждой стороны их может быть несколько: во всю высоту, над джойстиком,
	над кнопкой действия, над колонкой кнопок). Карточка — с пропорцией aspect (ширина / высота),
	её «отпечаток» шире на span (баннер выступает за края), хотим размер want (ширина, без span),
	не уже minWidth — иначе этой полосы нет. Из всех полос — та, где карточка крупнее (слева —
	охотнее, × leftBias: рыбак с трофеем между карточкой и кнопкой «ЗАБРАТЬ!»); по высоте —
	напротив середины рыбака с трофеем, в пределах полосы (dockSide). Возвращает прямоугольник
	самой карточки (без span), сторону и край keepout с этой стороны; места нигде нет — nil.
]]
function FishingLayout.cardDock(
	keepout: Rect,
	bands: { DockBand },
	want: number,
	minWidth: number,
	aspect: number,
	span: number,
	leftBias: number?
): (Rect?, number?, number?)
	local best: Rect? = nil
	local bestSide, bestArea = 0, 0
	local foot = aspect * span -- пропорция «отпечатка»
	for _, band in bands do
		-- Ближний к рыбаку край полосы: его край или, если препятствие ещё ближе, край полосы.
		local near = if band.side < 0 then math.min(keepout.x0, band.right) else math.max(keepout.x1, band.left)
		local slot = FishingLayout.dockSide(
			band.side,
			{ x0 = near, y0 = keepout.y0, x1 = near, y1 = keepout.y1 },
			Vector2.new(want * span, want / aspect),
			minWidth * span,
			band.top,
			band.bottom,
			foot,
			if band.side < 0 then band.left else band.right
		)
		if slot then
			local area = (slot.x1 - slot.x0) * (slot.y1 - slot.y0) * (if band.side < 0 then leftBias or 1.1 else 1)
			if area > bestArea then
				best, bestSide, bestArea = slot, band.side, area
			end
		end
	end
	if not best then
		return nil, nil, nil
	end
	local w = (best.x1 - best.x0) / span
	local cx = (best.x0 + best.x1) / 2
	return { x0 = cx - w / 2, y0 = best.y0, x1 = cx + w / 2, y1 = best.y1 },
		bestSide,
		if bestSide < 0 then keepout.x0 else keepout.x1
end

-- Площадь пересечения двух прямоугольников (0 — не пересекаются).
local function overlapArea(a: Rect, b: Rect): number
	return math.max(0, math.min(a.x1, b.x1) - math.max(a.x0, b.x0))
		* math.max(0, math.min(a.y1, b.y1) - math.max(a.y0, b.y0))
end
FishingLayout.overlapArea = overlapArea

--[[
	Запасное место карточки, когда сбоку от рыбака с трофеем не помещается ни одна (UI v5, D1/D2:
	огромный мифический трофей на маленьком телефоне): карточка размером w × h (её «отпечаток» шире
	на span — баннер выступает) в одной из полос bands там, где она закрывает keepout (рыбака с
	трофеем) МЕНЬШЕ всего — прижатая к краю полосы, к краю рыбака или напротив его середины; при
	равенстве — ближе к его середине по высоте. Возвращает прямоугольник самой карточки (без span),
	сторону (−1 — левее середины рыбака, 1 — правее) и сколько px² рыбака закрывает «отпечаток»;
	ни одна полоса не вмещает карточку — nil.
]]
function FishingLayout.leastCover(
	keepout: Rect,
	bands: { DockBand },
	w: number,
	h: number,
	span: number
): (Rect?, number?, number?)
	local fw = w * span
	local mid = (keepout.y0 + keepout.y1) / 2
	local best: Rect? = nil
	local bestCover, bestOff = math.huge, math.huge
	for _, band in bands do
		if band.right - band.left < fw or band.bottom - band.top < h then
			continue
		end
		local xs = { band.left, band.right - fw, keepout.x0 - fw, keepout.x1 }
		local ys = { band.top, band.bottom - h, keepout.y0 - h, keepout.y1, mid - h / 2 }
		for _, x in xs do
			x = math.clamp(x, band.left, band.right - fw)
			for _, y in ys do
				y = math.clamp(y, band.top, band.bottom - h)
				local foot = { x0 = x, y0 = y, x1 = x + fw, y1 = y + h }
				local cover = overlapArea(foot, keepout)
				local off = math.abs(y + h / 2 - mid)
				if cover < bestCover - 0.5 or (cover < bestCover + 0.5 and off < bestOff) then
					best, bestCover, bestOff = foot, cover, off
				end
			end
		end
	end
	if not best then
		return nil, nil, nil
	end
	local inset = (fw - w) / 2
	local rect = { x0 = best.x0 + inset, y0 = best.y0, x1 = best.x1 - inset, y1 = best.y1 }
	local side = if (rect.x0 + rect.x1) / 2 < (keepout.x0 + keepout.x1) / 2 then -1 else 1
	return rect, side, bestCover
end

return FishingLayout
