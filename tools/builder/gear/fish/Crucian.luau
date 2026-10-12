-- Карасик (Common): a small, almost round ginger fish with big eyes and a little smile under the
-- face. Narrower back and keel round off the cross-section; the tail flares out in steps into a
-- small fan; the long dorsal is swept back.
return {
	id = "Crucian",
	kind = "fish",
	title = "Карасик",
	rarity = "Common",
	length = 8,
	blocks = {
		{ "Body", { -2, -0.5, -1.5 }, { 6, 2, 3 }, "FF9A3C", ru = "тело" },
		{ "Back", { -1, 1.5, -1 }, { 4, 1, 2 }, "FF9A3C", ru = "спинка" },
		{ "Belly", { -2, -1.5, -1.5 }, { 5.5, 1, 3 }, "FFD08A", ru = "брюшко" },
		{ "Keel", { -1, -2.5, -1 }, { 3.5, 1, 2 }, "FFD08A", ru = "низ брюшка" },
		{ "Mouth", { 3.5, -1, -1 }, { 0.5, 0.5, 2 }, "3A1F2B", ru = "улыбка", keep = true },
		{ "EyeL", { 1, -0.5, 1.5 }, { 2.5, 2.5, 0.5 }, "FFFFFF", ru = "глаз левый", keep = true },
		{ "EyeR", { 1, -0.5, -2 }, { 2.5, 2.5, 0.5 }, "FFFFFF", ru = "глаз правый", keep = true },
		{ "PupilL", { 2, 0, 2 }, { 1, 1.5, 0.5 }, "1B1B2F", ru = "зрачок левый", keep = true },
		{ "PupilR", { 2, 0, -2.5 }, { 1, 1.5, 0.5 }, "1B1B2F", ru = "зрачок правый", keep = true },
		{ "Dorsal", { -1.5, 2.5, -0.5 }, { 3, 1.5, 1 }, "E8792A", ru = "спинной плавник" },
		{ "TailStem", { -3, -1, -0.5 }, { 1, 2, 1 }, "E8792A", ru = "хвостовой стебель" },
		{ "TailFan", { -3.5, -1.5, -0.5 }, { 0.5, 3, 1 }, "E8792A", ru = "хвост, середина веера" },
		{ "Tail", { -4.5, -2, -0.5 }, { 1, 4, 1 }, "E8792A", ru = "хвост, край веера" },
	},
}
