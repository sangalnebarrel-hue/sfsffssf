--!strict
--[[
	FishConfig — рыбы, редкости и мутации (баланс улова).

	Как выпадает рыба (FishingRules.RollFish, сервер):
	  1) редкость — по весам Rarities[*].Weight (удочка с удачей Luck поднимает веса редких,
	     см. LuckPower);
	  2) вид — среди рыб этой редкости по весам Fish[*].Weight;
	  3) размер — от MinKg до MaxKg (мелкие чаще), цена растёт с размером (SizeValue);
	  4) мутация — редкий шанс (Mutations[*].Chance), умножает цену (Multiplier).

	Модели рыб собираются из блок-спецификаций tools/builder/gear/fish/<Id>.luau
	(сборщик проверяет, что Id здесь и там совпадают).
	Модуль «чистый» (без require), его читает и сборщик места.
]]

export type Rarity = {
	Id: string,
	Name: string, -- как показывать игроку: «Мифическая»
	-- То же строчными: «мифическая» (string.lower в Luau не понимает кириллицу) — для фраз
	-- вроде «Рыбак: мифическая «Рыба-дракон»!» (объявление FishingService).
	NameLower: string,
	Weight: number, -- относительный шанс редкости
	LuckPower: number, -- вес умножается на Luck ^ LuckPower (удочки лучше — редкие чаще)
	Color: Color3, -- цвет плашки редкости в интерфейсе
}

export type Fish = {
	Id: string, -- совпадает с id блок-спецификации (tools/builder/gear/fish)
	Name: string,
	Rarity: string,
	Weight: number, -- шанс вида внутри своей редкости
	Value: number, -- базовая цена продажи (Этап 3), монет
	Income: number, -- доход в аквариуме (Этап 3), монет в секунду
	MinKg: number,
	MaxKg: number,
}

export type Mutation = {
	Id: string, -- "Gold" | "Neon" | "Rainbow" — как в tools/builder/Gear.luau
	Name: string, -- прилагательное для карточки улова («Золотой Карасик»)
	Chance: number, -- 0..1, вероятность именно этой мутации (сумма всех ≤ 1)
	Multiplier: number, -- множитель цены и дохода
	Color: Color3, -- цвет значка мутации в интерфейсе
}

local FishConfig = {
	-- Шансы видов (вес редкости × доля вида): Карасик 35 %, Окунь 25 %, Фугу 25 %,
	-- Меч-рыба 10 %, Акулёнок 4 %, Рыба-дракон 1 % — с базовой удочкой.
	Rarities = {
		{
			Id = "Common",
			Name = "Обычная",
			NameLower = "обычная",
			Weight = 60,
			LuckPower = 0,
			Color = Color3.fromRGB(150, 160, 172),
		},
		{
			Id = "Rare",
			Name = "Редкая",
			NameLower = "редкая",
			Weight = 25,
			LuckPower = 1,
			Color = Color3.fromRGB(64, 140, 230),
		},
		{
			Id = "Epic",
			Name = "Эпическая",
			NameLower = "эпическая",
			Weight = 10,
			LuckPower = 1.5,
			Color = Color3.fromRGB(160, 84, 226),
		},
		{
			Id = "Legendary",
			Name = "Легендарная",
			NameLower = "легендарная",
			Weight = 4,
			LuckPower = 2,
			Color = Color3.fromRGB(246, 178, 34),
		},
		{
			Id = "Mythic",
			Name = "Мифическая",
			NameLower = "мифическая",
			Weight = 1,
			LuckPower = 2.5,
			Color = Color3.fromRGB(255, 72, 170),
		},
	} :: { Rarity },

	Fish = {
		{
			Id = "Crucian",
			Name = "Карасик",
			Rarity = "Common",
			Weight = 35,
			Value = 10,
			Income = 1,
			MinKg = 0.3,
			MaxKg = 1.2,
		},
		{
			Id = "Perch",
			Name = "Окунь-полосатик",
			Rarity = "Common",
			Weight = 25,
			Value = 15,
			Income = 1.5,
			MinKg = 0.4,
			MaxKg = 1.8,
		},
		{
			Id = "Puffer",
			Name = "Фугу-пуфик",
			Rarity = "Rare",
			Weight = 1,
			Value = 45,
			Income = 4,
			MinKg = 0.8,
			MaxKg = 3,
		},
		{
			Id = "Swordfish",
			Name = "Меч-рыба",
			Rarity = "Epic",
			Weight = 1,
			Value = 140,
			Income = 12,
			MinKg = 25,
			MaxKg = 90,
		},
		{
			Id = "SharkPup",
			Name = "Акулёнок",
			Rarity = "Legendary",
			Weight = 1,
			Value = 450,
			Income = 40,
			MinKg = 12,
			MaxKg = 40,
		},
		{
			Id = "DragonFish",
			Name = "Рыба-дракон",
			Rarity = "Mythic",
			Weight = 1,
			Value = 1800,
			Income = 150,
			MinKg = 6,
			MaxKg = 18,
		},
	} :: { Fish },

	-- Один бросок на рыбу, шансы складываются: радужная 1 %, неоновая 3 %, золотая 6 %,
	-- без мутации — остальные 90 %.
	Mutations = {
		{
			Id = "Rainbow",
			Name = "Радужная",
			Chance = 0.01,
			Multiplier = 5,
			Color = Color3.fromRGB(255, 96, 200),
		},
		{ Id = "Neon", Name = "Неоновая", Chance = 0.03, Multiplier = 3, Color = Color3.fromRGB(60, 236, 220) },
		{ Id = "Gold", Name = "Золотая", Chance = 0.06, Multiplier = 2, Color = Color3.fromRGB(255, 200, 40) },
	} :: { Mutation },

	-- Цена и доход растут с размером: самая мелкая рыба вида — × SizeValue.Min,
	-- самая крупная — × SizeValue.Max. SizeBias > 1 — мелкие попадаются чаще крупных.
	SizeValue = { Min = 0.8, Max = 1.5 },
	SizeBias = 1.6,
}

return FishConfig
