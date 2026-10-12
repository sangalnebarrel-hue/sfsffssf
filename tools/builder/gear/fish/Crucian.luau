-- Карасик (Common): a small, almost round ginger fish with big eyes and a little smile.
return {
	id = "Crucian",
	kind = "fish",
	title = "Карасик",
	rarity = "Common",
	length = 8,
	blocks = {
		{ "Body", { -2.5, -1, -1.5 }, { 5, 3, 3 }, "FF9A3C", ru = "тело" },
		{ "Belly", { -2, -2.5, -1.5 }, { 4, 1.5, 3 }, "FFD08A", ru = "брюшко" },
		{ "Head", { 2.5, -1, -1 }, { 1, 2.5, 2 }, "FF9A3C", ru = "голова" },
		{ "Mouth", { 3.5, -0.5, -0.5 }, { 0.5, 0.5, 1 }, "3A1F2B", ru = "ротик", keep = true },
		{ "EyeL", { 0.5, 0, 1.5 }, { 2, 2, 0.5 }, "FFFFFF", ru = "глаз левый", keep = true },
		{ "EyeR", { 0.5, 0, -2 }, { 2, 2, 0.5 }, "FFFFFF", ru = "глаз правый", keep = true },
		{ "PupilL", { 1.5, 0.5, 2 }, { 1, 1, 0.5 }, "1B1B2F", ru = "зрачок левый", keep = true },
		{ "PupilR", { 1.5, 0.5, -2.5 }, { 1, 1, 0.5 }, "1B1B2F", ru = "зрачок правый", keep = true },
		{ "Dorsal", { -1.5, 2, -0.5 }, { 2, 1.5, 1 }, "E07424", ru = "спинной плавник" },
		{ "TailStem", { -3, -1, -0.5 }, { 0.5, 2, 1 }, "E07424", ru = "хвостовой стебель" },
		{ "Tail", { -4, -2, -0.5 }, { 1, 4, 1 }, "E07424", ru = "хвост" },
	},
}
