--!strict
--[[
	CatchFx — помощник карточки улова FishingController (стиль «Симулятор», UI v5): то, что не
	влезло бы в контроллер (у него мало свободных регистров, см. tests/compile_limits). Только
	цвета и движение карточки; где она встаёт — FishingLayout, когда что показывается — сам
	FishingController (раздел «Улов»). Ничего не подключает: только твины и таймеры.

	  • podiumLook / paintPodium — подиум-стойка под рыбой (CatchCard.Pedestal) в цветах редкости:
	    светлая крышка (с тенью рыбы), колонна со ⭐ (светлее цвета редкости → её цвет), тёмное
	    основание; обводки — её тёмный оттенок.
	  • nameColors — имя рыбы: белое → цвет редкости (с тёмной обводкой, как все надписи образца;
	    мифическая — радуга вдоль букв).
	  • birthPoint — где карточка рождается: в точке рыбы над головой; у карточки сбоку от рыбака —
	    там же, но внутри своего места (маленькая карточка не заходит на рыбака и трофей: растёт от
	    своего края к середине).
	  • birth — рождение: летит из этой точки на место (Quint Out), растёт с лёгким перелётом
	    (0.4 → 1.04 → 1) и доворачивается.
	  • slap — «наклейка» «НОВИНКА!» шлёпается на угол окна: падает крупной с доворотом, на касании
	    вздрагивает, белое кольцо и горсть искр.
	  • popStars — звёзды баннера выскакивают по очереди и качаются.
	  • punchChips — фишки веса и цены поднимаются по очереди с «ударом» (0.85 → 1.1 → 1), «тик»
	    всё выше.
	Всё, что живёт дольше вызова, отменяется уборкой trove (карточка закрылась — хвостов нет).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared:WaitForChild("Config"):WaitForChild("UIConfig"))
local UiFx = require(Shared:WaitForChild("UiFx"))
local Trove = require(Shared:WaitForChild("Util"):WaitForChild("Trove"))

local CatchFx = {}

local WHITE = UIConfig.White
local QUINT, QUAD, BACK = Enum.EasingStyle.Quint, Enum.EasingStyle.Quad, Enum.EasingStyle.Back
local OUT = Enum.EasingDirection.Out

type Style = UIConfig.RarityStyle

-- Рождение карточки: с какого масштаба, до какого перелёта, за сколько (рост; доворот и полёт —
-- за Time, Quint Out: без перелёта по месту, у рыбака).
local BIRTH = { From = 0.4, Peak = 1.04, Grow = 0.24, Settle = 0.18, Time = 0.35, Turn = -6 }

local function after(trove: Trove.Trove, delay: number, fn: () -> ())
	trove:Add(task.delay(delay, fn))
end

-- Подиум (стойка): колонна — от светлого цвета редкости к её цвету, обводки — её тёмный оттенок.
function CatchFx.podiumLook(style: Style): UIConfig.Swatch
	return { Top = UiFx.lighten(style.Top, 0.2), Bottom = style.Bottom, Lip = style.Lip }
end

-- Покрасить подиум: колонна (сам Pedestal), светлая крышка Cap (её видно сверху) и тёмное
-- основание Base.
function CatchFx.paintPodium(pedestal: GuiObject, style: Style)
	UiFx.setCandy(pedestal, CatchFx.podiumLook(style))
	local cap = pedestal:FindFirstChild("Cap")
	if cap and cap:IsA("GuiObject") then
		UiFx.setCandy(
			cap,
			{ Top = UiFx.lighten(style.Top, 0.7), Bottom = UiFx.lighten(style.Top, 0.3), Lip = style.Lip }
		)
	end
	local base = pedestal:FindFirstChild("Base")
	if base and base:IsA("GuiObject") then
		UiFx.setCandy(base, { Top = style.Bottom, Bottom = UiFx.darken(style.Bottom, 0.25), Lip = style.Lip })
	end
end

-- Имя рыбы: заливка (TextFill) и её поворот. Обводка — тёмная (сборщик), как у всех надписей.
function CatchFx.nameColors(rarityId: string, style: Style): (ColorSequence, number)
	if style.Rainbow then
		return UiFx.sequence(UIConfig.Rainbow), 0
	elseif rarityId == "Common" then
		return ColorSequence.new(WHITE, UiFx.lighten(style.Bottom, 0.4)), 90
	end
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, WHITE),
		ColorSequenceKeypoint.new(0.45, style.Top),
		ColorSequenceKeypoint.new(1, style.Bottom),
	}),
		90
end

--[[
	Точка рождения карточки (px родителя): from — где рыба над головой (nil — середина места). У
	карточки сбоку от рыбака (docked) — ближайшая к рыбе точка, где карточка размером BIRTH.From
	ещё целиком на своём месте: она рождается у своего края со стороны рыбака и растёт к середине,
	ни на миг не заходя на рыбака и трофей.
]]
function CatchFx.birthPoint(from: Vector2?, center: Vector2, size: Vector2, docked: boolean): Vector2
	if not from then
		return center
	elseif not docked then
		return from
	end
	local half = size * (1 - BIRTH.From) / 2
	return Vector2.new(
		math.clamp(from.X, center.X - half.X, center.X + half.X),
		math.clamp(from.Y, center.Y - half.Y, center.Y + half.Y)
	)
end

-- Рождение: из start (px) на место rest (Position) — полёт и доворот Quint Out, рост с перелётом.
function CatchFx.birth(card: GuiObject, start: Vector2, rest: UDim2)
	card.Position = UDim2.fromOffset(math.round(start.X), math.round(start.Y))
	UiFx.tween(card, BIRTH.Time, { Position = rest }, QUINT, OUT)
	UiFx.punch(card, { from = BIRTH.From, peak = BIRTH.Peak, up = BIRTH.Grow, settle = BIRTH.Settle })
	card.Rotation = BIRTH.Turn
	UiFx.tween(card, BIRTH.Time, { Rotation = 0 }, QUINT, OUT)
end

--[[
	«НОВИНКА!» шлёпается, как наклейка: падает крупной (2.4) с доворотом −18° и садится (Back
	Out), на касании вздрагивает (лёгкая тряска), от неё — белое кольцо и горсть искр (в слое
	layer, точка at — её середина в долях слоя). Возвращает stop искр (в уборку карточки).
]]
function CatchFx.slap(stamp: GuiObject, layer: GuiBase2d, at: Vector2, trove: Trove.Trove): () -> ()
	local scale = UiFx.scaleOf(stamp)
	scale.Scale = 2.4
	UiFx.tween(scale, 0.26, { Scale = 1 }, BACK, OUT)
	local rest = stamp.Rotation
	stamp.Rotation = rest - 18
	UiFx.tween(stamp, 0.26, { Rotation = rest }, BACK, OUT)
	local sparks: () -> () = function() end
	after(trove, 0.16, function()
		if not stamp.Visible then
			return
		end
		UiFx.shake(stamp, 0.012, 0.16)
		UiFx.glowRing(stamp, { color = WHITE, scale = 1.35, thickness = 3, time = 0.32 })
		sparks = UiFx.burst(layer, {
			origin = at,
			count = 8,
			colors = { WHITE, UIConfig.Palette.Berry.Top, UIConfig.Palette.Gold.Top },
			power = 0.55,
			z = 13,
		})
		UiFx.sound("pop", 0.45, 1.35)
	end)
	return function()
		sparks()
	end
end

-- Звёзды баннера выскакивают по очереди (с доворотом наружу) и, встав, качаются.
function CatchFx.popStars(banner: GuiObject, delay: number, trove: Trove.Trove)
	for index, name in { "StarLeft", "StarRight" } do
		local star = banner:FindFirstChild(name)
		if star and star:IsA("GuiObject") then
			local wait = delay + (index - 1) * 0.06
			UiFx.popIn(star, { from = 0, time = 0.3, delay = wait, rotate = if index == 1 then -40 else 40 })
			after(trove, wait + 0.3, function()
				UiFx.wiggle(star, 16, 3, 0.5)
			end)
		end
	end
end

--[[
	Фишки поднимаются по очереди (через gap): каждая — из-под своего места (на rise px ниже) с
	«ударом» 0.85 → 1.1 → 1, «тик» всё выше (1.1 → 1.25). homes — их места «в покое».
]]
function CatchFx.punchChips(chips: { GuiObject }, homes: { UDim2 }, rise: number, gap: number, trove: Trove.Trove)
	for index, chip in chips do
		local home = homes[index]
		after(trove, (index - 1) * gap, function()
			chip.Position = home + UDim2.fromOffset(0, math.round(rise))
			UiFx.tween(chip, 0.25, { Position = home }, QUAD, OUT)
			UiFx.punch(chip, { from = 0.85, peak = 1.1, up = 0.1, settle = 0.22 })
			UiFx.sound("tick", 0.3, 1.1 + 0.15 * (index - 1) / math.max(#chips - 1, 1))
		end)
	end
end

return CatchFx
