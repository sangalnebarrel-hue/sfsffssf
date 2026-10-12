-- Акулёнок (Legendary): a chibi shark pup. Big grey-blue head with a lower muzzle (Snout) over a
-- dark open grin with two hanging teeth; white belly under the head, a swept-back stepped dorsal and
-- saturated blue fins for contrast against the soft grey-blue body. Narrower tail section ending in a
-- forked shark tail whose upper lobe is bigger and reaches further back than the lower one. The
-- pectorals are one plate tucked under the body behind the belly (reads as two fins from any side).
return {
	id = "SharkPup",
	kind = "fish",
	title = "Акулёнок",
	rarity = "Legendary",
	length = 16,
	blocks = {
		{ "Body", { 0, -0.5, -3 }, { 6, 4, 6 }, "7A9CC8", ru = "голова" },
		{ "Snout", { 6, -0.5, -2.5 }, { 2, 3, 5 }, "7A9CC8", ru = "нос" },
		{ "Belly", { 1.5, -3, -3 }, { 4.5, 2.5, 6 }, "F4F8FF", ru = "белое брюшко" },
		{ "Mouth", { 6, -2, -2.5 }, { 1.5, 1.5, 5 }, "3A1F2B", ru = "улыбка", keep = true },
		{ "ToothL", { 7.5, -1.5, 0.5 }, { 0.5, 1, 1 }, "FFFFFF", ru = "зуб левый", keep = true },
		{ "ToothR", { 7.5, -1.5, -1.5 }, { 0.5, 1, 1 }, "FFFFFF", ru = "зуб правый", keep = true },
		{ "EyeL", { 3, 0, 3 }, { 3, 3.5, 0.5 }, "FFFFFF", ru = "глаз левый", keep = true },
		{ "EyeR", { 3, 0, -3.5 }, { 3, 3.5, 0.5 }, "FFFFFF", ru = "глаз правый", keep = true },
		{ "PupilL", { 4, 0.5, 3.5 }, { 1.5, 2.5, 0.5 }, "1B1B2F", ru = "зрачок левый", keep = true },
		{ "PupilR", { 4, 0.5, -4 }, { 1.5, 2.5, 0.5 }, "1B1B2F", ru = "зрачок правый", keep = true },
		{
			"Dorsal1",
			{ -1, 3.5, -1 },
			{ 4, 2, 2 },
			"4470C0",
			ru = "спинной плавник (основание)",
		},
		{ "Dorsal2", { -1.5, 5.5, -0.5 }, { 2.5, 2.5, 1 }, "4470C0", ru = "спинной плавник (верх)" },
		{ "Pectorals", { -1, -1.5, -4.5 }, { 2.5, 1, 9 }, "4470C0", ru = "грудные плавники" },
		{ "TailStem", { -4, 0, -2 }, { 4, 3, 4 }, "7A9CC8", ru = "хвостовая часть" },
		{ "TailUp", { -7.5, 2, -0.5 }, { 3.5, 3.5, 1 }, "4470C0", ru = "хвост (верхняя лопасть)" },
		{ "TailLow", { -6, -1.5, -0.5 }, { 2, 2.5, 1 }, "4470C0", ru = "хвост (нижняя лопасть)" },
	},
}
