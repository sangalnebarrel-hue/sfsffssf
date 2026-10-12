-- Меч-рыба (Epic): a fast, confident blue swordfish. A dark-blue back stripe runs from the tail stem
-- forward and ends as a brow over the eyes (countershading, not a cap); big eyes with forward pupils
-- tucked under it give the confident look. A deep shoulder tapers to a thin tail stem; a long
-- grey-blue sword, a tall stepped violet sail and a stepped crescent tail (root bar + two lobes).
return {
	id = "Swordfish",
	kind = "fish",
	title = "Меч-рыба",
	rarity = "Epic",
	length = 16,
	blocks = {
		{ "Body", { -3, -2, -2 }, { 3.5, 3.5, 4 }, "2E7DF0", ru = "тело" },
		{ "Back", { -3, 1.5, -2 }, { 6.5, 1, 4 }, "2264D2", ru = "тёмная спинка и бровь" },
		{ "Head", { 0.5, -2, -1.5 }, { 3.5, 3.5, 3 }, "2E7DF0", ru = "голова" },
		{ "Belly", { -2, -3, -1.5 }, { 5.5, 1, 3 }, "F4F8FF", ru = "белое брюхо" },
		{ "Rear", { -5.5, -1, -1 }, { 2.5, 3, 2 }, "2E7DF0", ru = "хвостовой стебель" },
		{ "Sword", { 4, 0, -0.5 }, { 5, 1, 1 }, "9CB4D8", ru = "меч" },
		{ "Mouth", { 3.5, -2.5, -1 }, { 1, 0.5, 2 }, "3A1F2B", ru = "рот", keep = true },
		{ "EyeL", { 0.5, -1, 1.5 }, { 3, 2.5, 0.5 }, "FFFFFF", ru = "глаз левый", keep = true },
		{ "EyeR", { 0.5, -1, -2 }, { 3, 2.5, 0.5 }, "FFFFFF", ru = "глаз правый", keep = true },
		{ "PupilL", { 2, -0.5, 2 }, { 1.5, 2, 0.5 }, "1B1B2F", ru = "зрачок левый", keep = true },
		{ "PupilR", { 2, -0.5, -2.5 }, { 1.5, 2, 0.5 }, "1B1B2F", ru = "зрачок правый", keep = true },
		{ "Sail", { -3, 2.5, -0.5 }, { 3.5, 4.5, 1 }, "6A3CE0", ru = "парус (спинной плавник)" },
		{ "SailBack", { -5, 2, -0.5 }, { 2, 2.5, 1 }, "7A4EEA", ru = "хвост паруса" },
		{ "TailRoot", { -6.5, -2, -0.5 }, { 1, 5, 1 }, "6A3CE0", ru = "хвост, основание" },
		{ "TailTop", { -8, 2, -0.5 }, { 1.5, 3.5, 1 }, "6A3CE0", ru = "хвост, верхний серп" },
		{ "TailBottom", { -8, -4.5, -0.5 }, { 1.5, 3.5, 1 }, "6A3CE0", ru = "хвост, нижний серп" },
	},
}
