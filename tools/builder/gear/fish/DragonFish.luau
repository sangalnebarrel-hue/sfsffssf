-- Рыба-дракон (Mythic): the rarest fish in the game. Violet dragon head with a lighter muzzle and
-- big eyes, gold horns at the head corners and long gold whiskers that reach forward past the nose
-- and droop (a dragon moustache); a glowing turquoise crest of three spikes rising towards the head;
-- pink belly; the tail flows violet -> pink tail root -> a big turquoise fan split into an upper and
-- a lower feather.
return {
	id = "DragonFish",
	kind = "fish",
	title = "Рыба-дракон",
	rarity = "Mythic",
	length = 20,
	blocks = {
		{ "Body", { -1, -1, -3.5 }, { 8, 5, 7 }, "B04AE0", ru = "голова" },
		{ "Snout", { 7, -1, -2.5 }, { 2, 3.5, 5 }, "C068F0", ru = "морда" },
		{ "Belly", { 0, -3.5, -3 }, { 6.5, 2.5, 6 }, "FF6AC8", ru = "розовое брюшко" },
		{ "Mouth", { 9, -0.5, -2 }, { 0.5, 1, 4 }, "3A1F2B", ru = "рот", keep = true },
		{ "EyeL", { 3, 0, 3.5 }, { 3.5, 3.5, 0.5 }, "FFFFFF", ru = "глаз левый", keep = true },
		{ "EyeR", { 3, 0, -4 }, { 3.5, 3.5, 0.5 }, "FFFFFF", ru = "глаз правый", keep = true },
		{ "PupilL", { 4.5, 0.5, 4 }, { 1.5, 2.5, 0.5 }, "1B1B2F", ru = "зрачок левый", keep = true },
		{ "PupilR", { 4.5, 0.5, -4.5 }, { 1.5, 2.5, 0.5 }, "1B1B2F", ru = "зрачок правый", keep = true },
		{ "HornL", { 5, 4, 2 }, { 1.5, 3, 1.5 }, "FFD24A", ru = "рог левый" },
		{ "HornR", { 5, 4, -3.5 }, { 1.5, 3, 1.5 }, "FFD24A", ru = "рог правый" },
		{ "WhiskerL", { 8, 0.5, 2.5 }, { 3, 1, 1 }, "FFD24A", ru = "ус левый" },
		{ "WhiskerR", { 8, 0.5, -3.5 }, { 3, 1, 1 }, "FFD24A", ru = "ус правый" },
		{ "WhiskerTipL", { 10.5, -1.5, 2.5 }, { 1, 2, 1 }, "FFD24A", ru = "кончик уса левый" },
		{ "WhiskerTipR", { 10.5, -1.5, -3.5 }, { 1, 2, 1 }, "FFD24A", ru = "кончик уса правый" },
		{
			"Crest1",
			{ 2.5, 4, -0.5 },
			{ 1.5, 4.5, 1 },
			"3EF0E0",
			ru = "светящийся гребень 1",
			neon = true,
		},
		{
			"Crest2",
			{ -0.5, 4, -0.5 },
			{ 1.5, 3.5, 1 },
			"3EF0E0",
			ru = "светящийся гребень 2",
			neon = true,
		},
		{
			"Crest3",
			{ -3.5, 3.5, -0.5 },
			{ 1.5, 2.5, 1 },
			"3EF0E0",
			ru = "светящийся гребень 3",
			neon = true,
		},
		{
			"TailMid",
			{ -4.5, -1, -2 },
			{ 3.5, 4.5, 4 },
			"FF6AC8",
			ru = "розовый хвостовой стебель",
		},
		{
			"TailUp",
			{ -8.5, 2, -0.5 },
			{ 4, 6.5, 1 },
			"40D8D0",
			ru = "хвост (верхнее перо веера)",
		},
		{ "TailLow", { -8.5, -5, -0.5 }, { 4, 6, 1 }, "40D8D0", ru = "хвост (нижнее перо веера)" },
	},
}
