--!strict
--[[
	FisherPoses — данные процедурной анимации рыбака (FisherAnimController): ключевые позы и
	тайминги. Чистые данные, без логики; позы проверены листами контактов
	(tools/preview/pose_sheet.py — каждая поза с камеры за спиной и сбоку).

	Поза — таблица «канал → поворот» (каналы — FisherRig.CHANNELS: Root, Waist, Neck, RShoulder,
	RElbow, RWrist, LShoulder, LElbow, LWrist, RHip, LHip, RKnee, LKnee, RAnkle, LAnkle).
	Углы в градусах { x, y, z } в пространстве Part0 сустава («торс»: X вправо, Y вверх, Z назад)
	ОТНОСИТЕЛЬНО ПОЗЫ ПОКОЯ (руки опущены): FisherRig.rot(x, y, z) — сначала развести вбок (z),
	потом поднять вперёд-вверх (x > 0), потом повернуть вокруг вертикали (y > 0 — влево).
	Root — ещё и сдвиг таза { x, y, z, dx, dy, dz }: studs в пространстве HumanoidRootPart
	(у стандартного персонажа; FisherRig масштабирует по росту, на R6 сдвиг не применяется —
	ноги R6 не сгибаются). Канала нет в позе — его ведёт Animator (обычная анимация Roblox).
	Hold — поза «toolnone» стандартного Animate (рука с удочкой вперёд, удочка на 35° вверх —
	под неё сделан Grip удочки, tools/builder/Assets.luau).

	Модуль «чистый» (без require): его читает и инструмент превью поз (tools/preview/pose_dump.luau).
]]

export type Angles = { number }

local FisherPoses = {}

FisherPoses.Poses = {
	-- Удочка в руке, ничего не происходит (= toolnone): удочка ≈35° вверх.
	Hold = {
		RShoulder = { 90, 0, 0 },
	},
	-- Взял удочку: поднял, глянул на кончик (≈0,5 с) и обратно в Hold.
	Ready = {
		RShoulder = { 118, 0, 8 },
		RElbow = { 20, 0, 0 },
		RWrist = { 14, 0, 0 },
		Waist = { 4, -6, 0 },
		Neck = { 8, -14, 0 },
	},
	-- Ждём поклёвку: удочка ≈48°, левая рука у катушки, взгляд на воду.
	Wait = {
		RShoulder = { 68, -4, 6 },
		RElbow = { 30, 0, 0 },
		RWrist = { 5, 0, 0 },
		LShoulder = { 40, -24, 0 },
		LElbow = { 62, 0, 0 },
		Waist = { 0, 0, 0 },
		Neck = { -10, 0, 0 },
	},
	-- Замах: кончик удочки высоко за головой, корпус довёрнут вправо.
	WindUp = {
		RShoulder = { 140, 0, 14 },
		RElbow = { 25, 0, 0 },
		RWrist = { 10, 0, 0 },
		LShoulder = { 55, -12, 0 },
		LElbow = { 35, 0, 0 },
		Waist = { 8, -20, 0 },
		Neck = { -4, 18, 0 },
		Root = { 0, 0, 0, 0, -0.12, 0.05 },
	},
	-- Миг броска (CastTime): удочка ≈47° вперёд — отсюда срывается поплавок.
	Release = {
		RShoulder = { 100, 0, 6 },
		RElbow = { 10, 0, 0 },
		RWrist = { 0, 0, 0 },
		LShoulder = { 30, 0, -20 },
		LElbow = { 20, 0, 0 },
		Waist = { -8, 10, 0 },
		Neck = { -6, -8, 0 },
		Root = { 0, 0, 0, 0, -0.15, -0.08 },
	},
	-- Проводка: удочка горизонтально к воде.
	Throw = {
		RShoulder = { 76, 0, 4 },
		RElbow = { 0, 0, 0 },
		RWrist = { -10, 0, 0 },
		LShoulder = { 20, 0, -28 },
		LElbow = { 15, 0, 0 },
		Waist = { -10, 14, 0 },
		Neck = { -8, -10, 0 },
		Root = { 0, 0, 0, 0, -0.2, -0.12 },
	},
	-- Клюёт: подался вперёд, удочка ≈17° — держит наготове.
	Bite = {
		RShoulder = { 64, -4, 6 },
		RElbow = { 22, 0, 0 },
		RWrist = { -4, 0, 0 },
		LShoulder = { 46, -26, 0 },
		LElbow = { 66, 0, 0 },
		Waist = { -10, 0, 0 },
		Neck = { -16, 0, 0 },
		Root = { 0, 0, 0, 0, -0.18, -0.05 },
	},
	-- Подсечка: удочка рывком почти вертикально.
	Strike = {
		RShoulder = { 110, 0, 6 },
		RElbow = { 40, 0, 0 },
		RWrist = { 5, 0, 0 },
		LShoulder = { 75, -22, 0 },
		LElbow = { 70, 0, 0 },
		Waist = { 10, 0, 0 },
		Neck = { 0, 0, 0 },
		Root = { 0, 0, 0, 0, -0.1, 0.12 },
	},
	-- Борьба с рыбой: откинулся, ноги в упоре, удочка ≈65°, левая крутит катушку.
	Reel = {
		RShoulder = { 80, -6, 6 },
		RElbow = { 30, 0, 0 },
		RWrist = { 0, 0, 0 },
		LShoulder = { 52, -28, 0 },
		LElbow = { 76, 0, 0 },
		Waist = { 10, 0, 0 },
		Neck = { -6, 0, 0 },
		Root = { 0, 0, 0, 0, -0.22, 0.1 },
		RHip = { -12, 0, 8 },
		LHip = { 12, 0, -8 },
		RKnee = { -18, 0, 0 },
		LKnee = { -10, 0, 0 },
	},
	-- Сматываем леску без рыбы: удочка чуть выше, левая крутит катушку.
	Retract = {
		RShoulder = { 84, -4, 6 },
		RElbow = { 28, 0, 0 },
		RWrist = { 0, 0, 0 },
		LShoulder = { 50, -26, 0 },
		LElbow = { 72, 0, 0 },
		Waist = { 4, 0, 0 },
		Neck = { -8, 0, 0 },
	},
	-- Поймал: рывок — обе руки вверх, взгляд вверх за рыбой.
	Yank = {
		RShoulder = { 125, 0, 10 },
		RElbow = { 20, 0, 0 },
		RWrist = { 10, 0, 0 },
		LShoulder = { 110, -14, 0 },
		LElbow = { 40, 0, 0 },
		Waist = { 15, 0, 0 },
		Neck = { 20, 0, 0 },
		Root = { 0, 0, 0, 0, 0.05, 0.12 },
	},
	-- Трофей над головой (R15, удочка в руке): ладони под рыбой, кисть с удочкой согнута —
	-- удочка смотрит вперёд над водой, не протыкает рыбу и свою табличку справа.
	-- Шея почти прямо: рыба приварена к голове (FishingService.holdFish) и наклонялась бы с ней.
	TrophySling = {
		RShoulder = { 160, 0, 16 },
		RElbow = { 10, 0, 0 },
		RWrist = { -100, 0, 0 },
		LShoulder = { 160, 0, -16 },
		LElbow = { 10, 0, 0 },
		Waist = { 4, 0, 0 },
		Neck = { 4, 0, 0 },
	},
	-- … без удочки в руке.
	TrophyNoRod = {
		RShoulder = { 160, 0, 16 },
		RElbow = { 10, 0, 0 },
		RWrist = { 0, 0, 0 },
		LShoulder = { 160, 0, -16 },
		LElbow = { 10, 0, 0 },
		Waist = { 4, 0, 0 },
		Neck = { 4, 0, 0 },
	},
	-- … на R6 (нет локтя и кисти): правая рука с удочкой — вверх и в сторону.
	TrophyR6 = {
		RShoulder = { 150, 0, 42 },
		LShoulder = { 160, 0, -16 },
		Waist = { 4, 0, 0 },
		Neck = { 4, 0, 0 },
	},
	-- Рыба ушла: поник, удочка опущена (кончик над настилом), голова вниз.
	Slump = {
		RShoulder = { 62, 6, 4 },
		RElbow = { 5, 0, 0 },
		RWrist = { -5, 0, 0 },
		LShoulder = { 0, 0, 0 },
		LElbow = { 5, 0, 0 },
		Waist = { -14, 0, 0 },
		Neck = { -24, 0, 0 },
		Root = { 0, 0, 0, 0, -0.14, 0 },
	},
}

-- Порядок поз на листе контактов (превью).
FisherPoses.Order = {
	"Hold",
	"Ready",
	"Wait",
	"WindUp",
	"Release",
	"Throw",
	"Bite",
	"Strike",
	"Reel",
	"Retract",
	"Yank",
	"TrophySling",
	"TrophyNoRod",
	"TrophyR6",
	"Slump",
}

-- Тайминги, с (переходы — CFrame:Lerp каждого сустава с плавностью; см. FisherAnimController).
FisherPoses.Timing = {
	FadeIn = 0.15, -- слой включается (рыбак подошёл / начал)
	FadeOut = 0.4, -- … и выключается (обычная анимация возвращается)
	Ready = { Up = 0.25, Hold = 0.25, Down = 0.35 }, -- взял удочку в руку
	Linger = 4, -- после рыбалки / трофея / «взял удочку»: качаем удочку ещё столько, потом отпускаем
	-- Заброс: замах (сжимается, если CastTime близко), «взведён» с дрожью до CastTime − Swing,
	-- бросок к Release ровно в CastTime (поплавок срывается с кончика), проводка, успокоение.
	WindUp = 0.22,
	Swing = 0.1,
	Follow = 0.1,
	Settle = 0.45,
	MinSwing = 0.05,
	CastTimeout = 1, -- свой заброс «вслепую» (нажал): ответа сервера нет столько — опускаем
	Wait = 0.35, -- вход в ожидание без заброса (вошёл в игру, а поплавок уже на воде)
	Bite = { Startle = 0.18, Settle = 0.15 },
	Strike = { Up = 0.09, Hold = 0.06, Down = 0.3 },
	Reel = 0.3,
	Retract = { Up = 0.12, Crank = 0.45, Down = 0.3 },
	Caught = { Yank = 0.22, Raise = 0.25, LookUp = 0.5, Bounce = 0.45 }, -- Bounce: присел + подпрыгнул
	Lost = { Slump = 0.25, ShakeFrom = 0.2, ShakeTo = 0.8, Hold = 1.1, Recover = 0.35 },
	TrophyDown = 0.4,
	Cancel = 0.3,
}

return FisherPoses
