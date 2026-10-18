--!strict
--[[
	EconomyConfig — деньги (Этап 3): доход садка, продажа рыбы, ларьки «ПРОДАТЬ РЫБУ», вид сумм,
	таблица игроков (leaderstats).

	Как это работает (подробно — docs/stage3_design.md, §3):
	  • деньги — целые монеты от 0 до MaxMoney, пишет их только EconomyService (AddMoney /
	    SpendMoney на сервере); у новичка StartMoney;
	  • доход: раз в IncomeTick секунд сервер начисляет каждому игроку сумму дохода его рыб
	    (FishData.Income × IncomeScale, хранится в десятых — TankRules.Income10); остаток меньше
	    монеты копится до следующего раза; после «подвисания» сервера начисляется не больше
	    MaxCatchUp тиков сразу;
	  • продажа: цена рыбы сейчас (TankRules.CurrentValue: её цена × рост в садке × SellScalePct %)
	    × ставку места — HomeRatePct % из панели садка где угодно, MarketRatePct % у любого ларька
	    SellPoints (рынок на острове и 4 ларька на мостах); ставку ларька сервер даёт, когда игрок
	    MarketDwell проверок подряд (раз в секунду) стоит не дальше Range от ларька — или сразу,
	    когда он подержал кнопку «Продать рыбу» у ларька (без телепорта: MarketJump);
	  • в Этапе 3 держать рыбу всегда выгоднее, чем продавать (доход ≈ 98 % всех денег) — ставки и
	    SellScalePct — ручки Этапа 5.
	Каждое число времени — на своей строке: тесты подменяют его в тексте модуля (boot с patches).
	Модуль «чистый» (без require), его читает и сборщик места.
]]

export type SellPoint = {
	Id: string, -- "Market" | "Kiosk1".."Kiosk4" — TankEvent "Open" Place, атрибут SellPlace
	Path: string, -- Attachment кнопки в Workspace (через точки)
	Name: string, -- ObjectText кнопки и заголовок места в панели
	Range: number, -- studs от Attachment до HumanoidRootPart, где действует ставка ларька
	Word: boolean?, -- над ним слово «РЫНОК +50%!» (TankWorldController; только рынок на острове)
}

local EconomyConfig = {
	StartMoney = 0, -- у нового игрока
	MaxMoney = 1e15, -- больше не бывает (целые числа точны); AddMoney обрезает (+ одно предупреждение)

	IncomeTick = 1, -- секунд между начислениями дохода (один общий цикл сервера)
	MaxCatchUp = 3, -- не больше стольких тиков за одно пробуждение цикла (без «подарка» за лаг)
	IncomeScale = 1, -- × Income рыбы (ручка Этапа 5)

	-- Ставки — целые проценты (цена считается в целых числах, без 0.999…).
	SellScalePct = 100, -- × цена продажи (не меняет цену на карточке улова; ручка Этапа 5)
	HomeRatePct = 100, -- продажа из панели садка где угодно
	MarketRatePct = 150, -- у любого ларька «ПРОДАТЬ РЫБУ» (рынок на острове и 4 на мостах)
	MarketDwell = 2, -- столько проверок подряд у ларька — и действует ставка рынка
	-- Скачок между проверками дальше WalkSpeed × dt × SpeedFactor + Slack studs по горизонтали
	-- (телепорт; прыжок и падение — нет) или новый персонаж — ставка ларька ждёт ещё Penalty
	-- чистых проверок (≈ секунд), и кнопка ларька её тоже не даёт: «телепортировался к ларьку и
	-- сразу продал» — по ×1. Вход, «Домой» и возрождение ставят игрока у его базы — оттуда до
	-- любого ларька дольше Penalty секунд пути.
	MarketJump = {
		SpeedFactor = 2,
		Slack = 8,
		Penalty = 5,
	},

	-- Ларьки: сервер ищет ближайший в Range от своей проверки позиции игрока (MarketService).
	SellPoints = {
		{
			Id = "Market",
			Path = "Map.Hub.FishMarket.Scales.SellPromptAttachment",
			Name = "Рыбный рынок",
			Range = 12,
			Word = true,
		},
		{
			Id = "Kiosk1",
			Path = "Map.Bridges.Bridge_1.Lookout.SellKiosk.Scales.SellPromptAttachment",
			Name = "Ларёк",
			Range = 12,
		},
		{
			Id = "Kiosk2",
			Path = "Map.Bridges.Bridge_2.Lookout.SellKiosk.Scales.SellPromptAttachment",
			Name = "Ларёк",
			Range = 12,
		},
		{
			Id = "Kiosk3",
			Path = "Map.Bridges.Bridge_3.Lookout.SellKiosk.Scales.SellPromptAttachment",
			Name = "Ларёк",
			Range = 12,
		},
		{
			Id = "Kiosk4",
			Path = "Map.Bridges.Bridge_4.Lookout.SellKiosk.Scales.SellPromptAttachment",
			Name = "Ларёк",
			Range = 12,
		},
	} :: { SellPoint },

	-- Кнопка ларька (ProximityPrompt "SellPrompt"): открывает панель садка, не продаёт сама.
	-- ObjectText: «Рыбный рынок · +50%» ({name} — Name ларька, {bonus} — MarketRatePct − 100).
	Prompt = {
		Action = "Продать рыбу",
		Object = "{name} · +{bonus}%",
		HoldDuration = 0.25,
		MaxDistance = 10,
		Slack = 4, -- сервер ещё раз проверяет расстояние: не дальше MaxDistance + Slack
	},

	-- Как писать суммы (TankRules.FormatMoney / FormatRate): до ShortFrom — все цифры с пробелами
	-- («$12 345»), дальше — 3 значащие цифры вниз и самая крупная единица Suffixes, что не больше
	-- суммы («$1.23M», «$12.3M», «$123M», «$1.5B», «T», «Qa»). Доход — «+$4/с» (до $10 — с десятыми:
	-- «+$0.8/с»).
	Format = {
		ShortFrom = 1e6,
		Currency = "$",
		Suffixes = {
			{ Unit = 1e6, Text = "M" },
			{ Unit = 1e9, Text = "B" },
			{ Unit = 1e12, Text = "T" },
			{ Unit = 1e15, Text = "Qa" },
		},
		Rate = "/с",
		Loading = "$…", -- кошелёк, пока данные игрока грузятся дольше 3 с
	},

	-- Таблица игроков Roblox: «Деньги» первыми (по ним сортируется список), «Доход/с» (целые).
	Leaderstats = {
		Money = "Деньги",
		Income = "Доход/с",
	},

	-- (P2) по одному уведомлению за всё время на каждый рубеж (TankConfig.Texts.Milestone).
	Milestones = { 1000, 10000, 100000, 1000000 },
}

return EconomyConfig
