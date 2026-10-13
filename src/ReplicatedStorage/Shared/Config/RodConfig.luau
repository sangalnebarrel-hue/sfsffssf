--!strict
--[[
	RodConfig — удочки (баланс). Сейчас у всех стартовая (StartRod); остальные продаются
	в магазине на Этапе 5.

	Что даёт удочка лучше:
	  Luck        — удача: веса редкостей умножаются на Luck ^ LuckPower (FishConfig.Rarities),
	                1 = базовые шансы;
	  BiteSpeed   — поклёвка быстрее: время ожидания делится на это число;
	  ZoneBonus   — зелёная зона мини-игры шире на эту долю полосы (0.03 = +3 % ширины полосы);
	  CastDistance — дальность заброса от точки рыбалки, стадов (только внешний вид).

	Модели удочек собираются из блок-спецификаций tools/builder/gear/rods/*.luau
	(сборщик проверяет, что Id здесь и там совпадают).
	Модуль «чистый» (без require), его читает и сборщик места.
]]

export type Rod = {
	Id: string, -- совпадает с id блок-спецификации (tools/builder/gear/rods)
	Name: string, -- название в интерфейсе и в рюкзаке
	Tier: number,
	Price: number, -- цена в магазине (Этап 5), монет
	Luck: number,
	BiteSpeed: number,
	ZoneBonus: number,
	CastDistance: number,
}

local RodConfig = {
	StartRod = "RodBamboo",

	Rods = {
		{
			Id = "RodBamboo",
			Name = "Бамбуковая удочка",
			Tier = 1,
			Price = 0,
			Luck = 1,
			BiteSpeed = 1,
			ZoneBonus = 0,
			CastDistance = 22,
		},
		{
			Id = "RodSea",
			Name = "Морская удочка",
			Tier = 2,
			Price = 750,
			Luck = 1.3,
			BiteSpeed = 1.15,
			ZoneBonus = 0.02,
			CastDistance = 25,
		},
		{
			Id = "RodGolden",
			Name = "Золотая удочка",
			Tier = 3,
			Price = 4000,
			Luck = 1.7,
			BiteSpeed = 1.3,
			ZoneBonus = 0.04,
			CastDistance = 28,
		},
		{
			Id = "RodCrystal",
			Name = "Кристальная удочка",
			Tier = 4,
			Price = 15000,
			Luck = 2.2,
			BiteSpeed = 1.5,
			ZoneBonus = 0.06,
			CastDistance = 31,
		},
		{
			Id = "RodMythic",
			Name = "Мифическая удочка",
			Tier = 5,
			Price = 60000,
			Luck = 3,
			BiteSpeed = 1.75,
			ZoneBonus = 0.08,
			CastDistance = 34,
		},
	} :: { Rod },
}

return RodConfig
