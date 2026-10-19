--!strict
--[[
	DefenceConfig — защита базы (Этап 4): щит и бесплатные защиты, собака, сигнализация, замок,
	лист «ЗАЩИТА» (кнопка справа) и все их тексты.

	Как устроено (подробно — docs/stage4_design.md, §2):
	  • у базы одна защита ProtectUntil = позднейшая из: щит (кнопка, Shield.Duration секунд,
	    снова готов через Duration + Cooldown после включения, время готовности сохраняется),
	    защита после входа (JoinProtect; первая игра нового сохранения — «защита новичка»
	    JoinProtectFirst; быстрый перезаход — QuickRejoinProtect), после кражи («after» —
	    StealConfig.Limits.VictimImmunity) и «садок отдыхает» после второй кражи за 10 минут
	    («rest»). Пока база под защитой, у неё ничего не украсть; начал красть сам — твоя защита
	    гаснет;
	  • щит включается, только если защиты осталось меньше Shield.StackBelow секунд (DC-03), и
	    возвращает рыбу, которую уже несут (DC-01);
	  • собака (Dog.Price, один раз): спит во дворе (Dog.Rest), во время кражи бежит к вору
	    (RunSpeed) и ближе BiteRange замедляет его в Slow раз;
	  • сигнализация (Alarm.Price, один раз): лампа мигает у всех и так (Этап 4: тревога при каждой
	    краже); купленная — ещё и раннее «👀 Ника у тебя во дворе!», красная подсветка вора и сирена;
	  • замок: уровень LockLevel задаёт время удержания (Lock.Levels; без замка — Lock.BaseHold);
	    Этап 4 продаёт только уровни ≤ Lock.SaleMax (1), уровни 2–5 — магазину Этапа 5 (они уже
	    работают в игре).
	Тексты с {полями} — TextUtil.fill: {t} — StealRules.FormatClock («1:00»), {price} —
	TankRules.FormatMoney, {s} / {new} / {old} — секунды удержания, {n} — уровень замка.
	Каждое число — на своей строке: тесты подменяют его в тексте модуля (boot с patches).
	Модуль «чистый» (без require, только Color3 / Vector3), его читает и сборщик места
	(tools/builder/gui/Defence.luau, Hud.luau).
]]

local DefenceConfig = {
	Shield = {
		Price = 0, -- щит бесплатный
		Duration = 60, -- щит держится столько с …
		Cooldown = 180, -- … и снова готов через столько с после конца (240 с после включения)
		StackBelow = 60, -- включить можно, пока защиты осталось меньше стольких с (DC-03)
		JoinProtect = 90, -- защита после входа, с
		JoinProtectFirst = 300, -- первая игра нового сохранения (SaveCount 0 при загрузке): «защита новичка»
		QuickRejoin = 300, -- LastOnline (или уход с этого сервера) новее стольких с — короткая защита …
		QuickRejoinProtect = 20, -- … вот такая
		WarnLast = 10, -- фишка «🛡️ 0:09» пульсирует последние столько с
		EndingWarn = 15, -- «Скоро воры смогут красть…» за столько с до конца защиты входа / новичка
	},
	Dog = {
		Price = 6000,
		Rest = { X = 6, Z = 58 }, -- где спит во дворе (studs базы), мордой к воротам (DC-05)
		AlertDelay = 0.4, -- «ГАВ!» — и через столько с бежит
		RunSpeed = 24, -- к вору, studs/с
		HomeSpeed = 10, -- обратно на место, studs/с
		BiteRange = 5, -- ближе стольких studs (по горизонтали) вор замедлен …
		Slow = 0.5, -- … в столько раз …
		SlowLinger = 1, -- … и ещё столько с после
		Leash = 4, -- не дальше стольких studs за край участка
		Replicate = 0.2, -- атрибуты собаки — не чаще раза в столько с …
		MoveEpsilon = 0.25, -- … и DogPos — только если сдвинулась дальше стольких studs
		-- Собака перед галереями (z < Front), а вор в проходе галереи (|x| от Inner до Outer, z до
		-- Back): сначала к открытому концу прохода (±X, Z) — стены галереи не пробегает; ближе
		-- Reach studs к нему — дальше прямо к вору.
		Waypoint = {
			Front = 54.5,
			Back = 120.5,
			Inner = 22,
			Outer = 37,
			X = 27,
			Z = 54,
			Reach = 0.5,
		},
	},
	Alarm = {
		Price = 2500,
		IntruderEvery = 1, -- проверка гостей во дворе раз в столько с (только базы с сигнализацией)
		IntruderCoalesce = 45, -- одно раннее предупреждение на пару (гость, хозяин) за столько с; не под защитой
		IntruderLamp = 5, -- лампа мигает «гость» (AlarmState "intruder") столько с
	},
	Lock = {
		SaleMax = 1, -- самый сильный замок в продаже сейчас (0 — карточки нет); Этап 5 поднимает
		BaseHold = 3, -- без замка держать столько с
		Levels = { -- работают все уровни; Этап 5 продаёт 2..5
			{ Hold = 4, Price = 1500 },
			{ Hold = 5, Price = 5000 },
			{ Hold = 6, Price = 15000 },
			{ Hold = 7.5, Price = 40000 },
			{ Hold = 9, Price = 100000 },
		},
	},
	-- Лимит запросов ShieldActivate + DefenceBuy: запас Burst, пополняется Rate в секунду.
	Requests = {
		Burst = 4,
		Rate = 1,
	},
	-- Мир (TheftWorldController; всё — на клиенте).
	World = {
		LampPeriod = 0.5, -- лампа мигает раз в столько с (2 Гц; не чаще 3 Гц — светочувствительность)
		IntruderPeriod = 1, -- … при госте во дворе
		-- Лампа (Neon) мигает от тёмного LampDim до горячего LampOn — тёмный ↔ яркий, а не красный ↔
		-- красный (на красной базе так видно и издали); свет лампы и сирены — красный LightColor.
		LampDim = Color3.fromRGB(56, 10, 10),
		LampOn = Color3.fromRGB(255, 112, 84),
		LightColor = Color3.fromRGB(255, 52, 44),
		LampLight = { Range = 32, Brightness = 3 },
		SirenSpin = 1.2, -- сирена делает оборот за столько с
		BeepRange = 120, -- писк сирены слышно ближе стольких studs
		-- Купол щита: только у щита (DC-15), только у баз ближе Range к камере, на тач-экране — не
		-- больше PhoneMax ближайших; шар Ø 2 × Radius в Center (studs базы), прозрачность
		-- Transparency; камера или свой персонаж внутри — Inside, ближе Near studs к оболочке снаружи —
		-- плавно от Transparency к Inside (хозяин у спауна внутри купола, камера позади него — снаружи:
		-- купол не ложится на весь экран); появляется и уходит за Fade с.
		Dome = {
			Kinds = { shield = true } :: { [string]: boolean },
			PhoneMax = 2,
			Center = Vector3.new(0, 0, 88),
			Radius = 58,
			Transparency = 0.15,
			Inside = 0.8,
			Near = 16,
			Range = 260,
			Fade = 0.4,
		},
		StealWordRange = 90, -- «КРАДУТ!» над витриной видно до стольких studs (хозяин от спауна видит)
		WordRange = 120, -- «ВОР!», табличку рыбы на голове вора и «ГАВ!» видно до стольких studs
		-- Остальное — TheftWorldController (docs/stage4_design.md §5.3–5.4): проверка баз раз в
		-- CheckEvery с (цепочка task.delay; только пока у какой-то базы что-то идёт); лампа,
		-- сирена и подсветка вора — у баз ближе Range к камере (дальше — вид шаблона).
		CheckEvery = 0.5,
		Range = 260,
		-- Сирена: красный SpotLight (Range / Brightness / Angle) в лампе — их два, спиной друг к
		-- другу, оба наклонены вниз на Pitch° (красное пятно бежит по двору; полоборота твином —
		-- оборот за SirenSpin), и вдоль каждого — луч Beam (виден и днём, и на телефоне, где
		-- местного света нет): BeamLength studs, ширина BeamWidth0 у лампы → BeamWidth1 на конце,
		-- прозрачность BeamFade у лампы → 1; писк — раз в BeepPeriod с, громкость BeepVolume,
		-- слышно ближе BeepRange.
		Siren = {
			Range = 40,
			Brightness = 6,
			Angle = 50,
			Pitch = 38,
			BeamLength = 14,
			BeamWidth0 = 0.6,
			BeamWidth1 = 5,
			BeamFade = 0.35,
			BeepPeriod = 0.6,
			BeepVolume = 0.5,
		},
		-- Вор (с сигнализацией хозяина): Highlight (заливка Berry с прозрачностью Fill, обводка —
		-- Outline) и «ВОР!» над головой (Word: studs + px; Lift studs над макушкой; с рыбой на
		-- голове — над её табличкой).
		Mark = {
			Fill = 0.7,
			Outline = 0,
			Lift = 1.6,
			Word = { Width = 3.2, Height = 1.1, PixelsX = 30, PixelsY = 12, Outline = 2.5 },
		},
		-- Рыба на голове вора (StolenFish): покачивание ±Bob studs и поворот ±Sway° за Period с
		-- (зацикленный твин сварки), табличка «🥷 Окунь $45» (Plate: studs + px, на Gap studs над
		-- рыбой; появляется через Delay с — рыба ещё летит с витрины), видно до WordRange.
		Carried = {
			Bob = 0.15,
			Sway = 8,
			Period = 0.9,
			Plate = { Width = 5.2, Height = 1.2, PixelsX = 44, PixelsY = 14, Outline = 2.5 },
			Gap = 0.4,
			Delay = 0.35,
		},
		-- Собака на клиенте: ближе Range к камере — идёт за DogPos (догоняет с коэффициентом Follow:
		-- α = 1 − e^(−Follow·dt)), на бегу (быстрее RunFrom studs/с) подпрыгивает на Hop studs HopHz
		-- раз в секунду; лапы — на земле двора: луч вниз (только Grounds и Arcades базы) от GroundUp
		-- studs над точкой базы на GroundDown studs — при каждой новой DogPos и у места сна; «ГАВ!»
		-- (Bark: studs + px, всплывает на BarkRise за BarkTime с, едет с собакой; BarkLift studs над
		-- ней) — при тревоге и при укусе; пока вор замедлен — пыль у его ног (Dust пылинок раз в
		-- DustEvery с). Спит — «💤» над ней (Sleep: studs + px, Lift studs над макушкой, видно до
		-- SleepRange; неподвижное — в покое ни одного твина).
		Dog = {
			Range = 200,
			Follow = 12,
			RunFrom = 1.5,
			Hop = 0.35,
			HopHz = 4,
			GroundUp = 4,
			GroundDown = 8,
			Bark = { Width = 3, Height = 1.2, PixelsX = 30, PixelsY = 14 },
			BarkRise = 1.4,
			BarkTime = 0.9,
			BarkLift = 1.2,
			Dust = 3,
			DustEvery = 0.25,
			Sleep = { Width = 1.6, Height = 1.2, PixelsX = 16, PixelsY = 12, Lift = 0.5 },
			SleepRange = 60,
		},
		-- «🛡️ 4:12» над табличкой флага (Flag.Pole.SignAttachment.OwnerSign; над ней только небо —
		-- не на полотнище флага): свой BillboardGui её размера (studs + px — читается с неё), сдвинут
		-- вверх на Raise своей высоты; строка — Line её высоты снизу, ширина — Wide, обводка Outline px.
		Flag = { Raise = 1.02, Line = 0.3, Wide = 0.7, Outline = 2 },
	},
	-- Лист «ЗАЩИТА» (Controllers/Sheet; px HUD — пишутся масштабом): Margin px до краёв, не больше
	-- MaxWidth × MaxHeight, шапка — Header высоты листа, высокий экран — от TallFrom px; карточка —
	-- ширина / высота CardAspect, не уже CardMin px (на маленьком телефоне 4-я карточка листается;
	-- на планшете и ПК все в ряд — выше, до CardAspectTall); не хватает денег — «ЕЩЁ $3 000» на
	-- кнопке цены NeedTime с (под пальцем, не уведомлением над листом).
	Panel = {
		Margin = 16,
		MaxWidth = 900,
		MaxHeight = 420,
		Header = 0.2,
		TallFrom = 600,
		CardAspect = 0.78,
		CardAspectTall = 0.52, -- планшет, ПК: карточки выше (крупный текст), лист — по ним
		CardMin = 96,
		NeedTime = 1.5, -- «ЕЩЁ $3 000» на кнопке цены, когда денег не хватает, с
	},
	-- Studio: защиты входа / новичка / после кражи / «отдыха» не дольше стольких с (щит — как
	-- есть); false — настоящие времена (DC-20). Живой сервер — никогда не Studio.
	Debug = {
		StudioProtect = 10,
	},

	Texts = {
		-- Кнопка справа (HUD.RightButtons.DefenceButton)
		Button = "ЗАЩИТА",
		ButtonAlert = "ЩИТ!", -- во время кражи у тебя, пока щит готов: одно нажатие — щит
		Ready = "ГОТОВ!", -- щит снова готов (на подписи кнопки 1.5 с)
		-- Щит и защиты (уведомления; фишка «🛡️ 0:42» у плашки базы)
		Chip = "{t}",
		Shield = {
			On = "Щит включён на {t}",
			Off = "Щит погас",
			Ready = "Щит снова готов!",
		},
		Protect = {
			newbie = "Защита новичка {t} 🛡️ — лови спокойно!",
			join = "Твой садок под защитой {t}",
			-- (🚨 — на плашке и на «таблетке» телефона; одна строка уведомления на любом экране)
			Ending = "Скоро воры! Увидишь 🚨 — жми 🛡️ ЩИТ!",
		} :: { [string]: string },
		-- Отказы (DefenceEvent "Denied" Text)
		Denied = {
			loading = "Загружаем твой садок…",
			nobase = "Сначала дождись своей базы",
			stealing = "Сначала закончи кражу",
			protected = "Ты и так под защитой — ещё {t}",
			cooldown = "Щит перезаряжается — ещё {t}",
			owned = "Уже куплено",
			max = "Замок уже лучший",
			soon = "Сильнее замки — скоро в магазине",
			money = "Не хватает: нужно {price}",
		} :: { [string]: string },
		-- Лист «ЗАЩИТА» (HUD.DefencePanel). Карточка: Name, Effect (строка действия; три строки не
		-- влезают и с меньшим кружком — EffectShort)
		Title = "ЗАЩИТА",
		Cards = {
			Shield = {
				Icon = "🛡️",
				Name = "ЩИТ",
				Effect = "Никто не украдёт 1\u{00A0}минуту",
				EffectShort = "Щит на 1\u{00A0}минуту",
			}, -- (1 минута = Shield.Duration)
			Dog = {
				Icon = "🐕",
				Name = "СОБАКА",
				Effect = "Вор с рыбой бежит вдвое медленнее",
				EffectShort = "Вор бежит медленнее",
			},
			Alarm = {
				Icon = "🚨",
				Name = "СИГНАЛИЗАЦИЯ",
				Short = "СИГНАЛКА", -- на карточке уже 120 px
				Effect = "Узнаешь о воре, как только он войдёт",
				EffectShort = "Узнаешь о воре заранее",
			},
			Lock = {
				Icon = "🔐",
				Name = "ЗАМОК",
				Effect = "Вору держать {new}\u{00A0}с вместо {old}", -- (неразрывный пробел: «4 с» не рвётся)
				EffectShort = "Вору держать {new}\u{00A0}с",
			},
		},
		Buy = {
			On = "ВКЛЮЧИТЬ", -- щит: включить
			Active = "🛡️ {t}", -- щит включён
			Wait = "⏳ {t}", -- щит перезаряжается
			Protected = "ТЫ ПОД ЗАЩИТОЙ", -- другая защита ≥ StackBelow
			Price = "💵 {price}",
			Confirm = "КУПИТЬ?",
			Bought = "✔️ КУПЛЕНО", -- штамп (плоский, без блика: не кнопка)
			Busy = "⏳",
			AfterTheft = "ПОСЛЕ КРАЖИ", -- щит, пока крадёшь сам (сервер откажет)
			Need = "ЕЩЁ {price}", -- не хватает денег: на кнопке под пальцем (Panel.NeedTime с)
		},
		LockSoon = "Сильнее замки — скоро в магазине", -- купленный замок: вместо строки действия (DC-11)
		LockSoonShort = "Новые замки — скоро!", -- … на узкой карточке
		LockLevel = "Замок ур. {n}",
		-- Куплено (уведомления)
		Bought = {
			Dog = "Собака охраняет твой двор!",
			Alarm = "Сигнализация включена!",
			Lock = "Замок: вору держать {s} с",
		} :: { [string]: string },
		-- Совет после кражи — один (DC-14): щит был готов и не нажат — про щит, иначе самая
		-- дешёвая защита, которой нет. «Совет» — значок TipIcon; каждый — одна строка уведомления
		-- и на маленьком телефоне (две строки закрыли бы голову рыбака)
		Tips = {
			Shield = "Щит бесплатный: увидишь 🚨 — жми 🛡️",
			Lock = "Замок — вору держать дольше ({price})",
			Alarm = "Сигналка — узнаешь о воре ({price})",
			Dog = "Собака замедлит вора ({price})",
		} :: { [string]: string },
		TipIcon = "💡",
		-- Мир: строка защит над большим аквариумом и под табличкой флага
		World = {
			Protect = "🛡️ {t}",
			Lock = "🔐{n}",
			Dog = "🐕",
			Alarm = "🚨",
			Separator = " · ",
			Sleep = "💤", -- над спящей собакой во дворе
		},
		-- Output (не интерфейс): одна строка при запуске в Studio
		StudioPrint = "[DefenceService] Studio: защита сокращена до {s} с (DefenceConfig.Debug.StudioProtect)",
	},
}

return DefenceConfig
