-- Окунь Полосатик (Common): a perky striped perch. The three dark stripes are body segments that
-- wrap all the way round; a chunky head with big eyes bulging above the head line and a dark jaw
-- tucked under the snout; the red dorsal and lower fins overhang the body behind them so they
-- read as swept back, and the tail is a broad red paddle.
return {
	id = "Perch",
	kind = "fish",
	title = "Окунь Полосатик",
	rarity = "Common",
	length = 10,
	blocks = {
		{ "Body", { 1.5, -1, -1.5 }, { 3, 2.5, 3 }, "B8E04A", ru = "голова" },
		{ "Stripe1", { 0.5, -1.5, -1.5 }, { 1, 3.5, 3 }, "3E7A2A", ru = "полоска 1" },
		{ "Mid1", { -1, -1.5, -1.5 }, { 1.5, 3.5, 3 }, "B8E04A", ru = "спинка" },
		{ "Stripe2", { -2, -1.5, -1.5 }, { 1, 3, 3 }, "3E7A2A", ru = "полоска 2" },
		{ "Mid2", { -3, -1, -1 }, { 1, 2.5, 2 }, "B8E04A", ru = "хвостик" },
		{ "Stripe3", { -4, -1, -1 }, { 1, 2, 2 }, "3E7A2A", ru = "полоска 3" },
		{ "Tail", { -5.5, -2, -0.5 }, { 1.5, 4, 1 }, "FF4A3A", ru = "хвост" },
		{ "Dorsal", { -2, 2, -0.5 }, { 3, 1.5, 1 }, "FF4A3A", ru = "колючий спинной плавник" },
		{ "Anal", { -2.5, -2.5, -0.5 }, { 1.5, 1, 1 }, "FF4A3A", ru = "нижний плавник" },
		{
			"Mouth",
			{ 3, -1.5, -1 },
			{ 1.5, 0.5, 2 },
			"3A1F2B",
			ru = "рот (нижняя челюсть)",
			keep = true,
		},
		{ "EyeL", { 1.5, -0.5, 1.5 }, { 2.5, 2.5, 0.5 }, "FFFFFF", ru = "глаз левый", keep = true },
		{ "EyeR", { 1.5, -0.5, -2 }, { 2.5, 2.5, 0.5 }, "FFFFFF", ru = "глаз правый", keep = true },
		{ "PupilL", { 2.5, 0, 2 }, { 1, 1.5, 0.5 }, "1B1B2F", ru = "зрачок левый", keep = true },
		{ "PupilR", { 2.5, 0, -2.5 }, { 1, 1.5, 0.5 }, "1B1B2F", ru = "зрачок правый", keep = true },
	},
}
