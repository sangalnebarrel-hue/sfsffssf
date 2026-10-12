-- Фугу Пуфик (Rare): a puffed-up, almost cubic yellow puffer. Huge surprised eyes, pink pursed lips
-- around a dark "o" mouth, a cream belly that rounds off the chin, a two-step spiky crest on top,
-- spikes out to both sides, back and belly, tiny orange paddle fins and a tiny tail.
return {
	id = "Puffer",
	kind = "fish",
	title = "Фугу Пуфик",
	rarity = "Rare",
	length = 10,
	blocks = {
		{ "Body", { -3, -1.5, -3.5 }, { 6.5, 5, 7 }, "FFE04A", ru = "тело-шарик" },
		{ "Belly", { -2.5, -3.5, -3 }, { 5.5, 2, 6 }, "FFF8E0", ru = "брюшко" },
		{ "Lips", { 3.5, -1.5, -2 }, { 0.5, 4, 4 }, "FF6F91", ru = "губки бантиком", keep = true },
		{ "Mouth", { 4, -0.5, -1 }, { 0.5, 2, 2 }, "3A1F2B", ru = "рот «о»", keep = true },
		{ "EyeL", { 0, -1, 3.5 }, { 3.5, 4, 0.5 }, "FFFFFF", ru = "глаз левый", keep = true },
		{ "EyeR", { 0, -1, -4 }, { 3.5, 4, 0.5 }, "FFFFFF", ru = "глаз правый", keep = true },
		{ "PupilL", { 1.5, 0.5, 4 }, { 1.5, 2, 0.5 }, "1B1B2F", ru = "зрачок левый", keep = true },
		{ "PupilR", { 1.5, 0.5, -4.5 }, { 1.5, 2, 0.5 }, "1B1B2F", ru = "зрачок правый", keep = true },
		{ "Tail", { -5, -1, -0.5 }, { 2, 3.5, 1 }, "FF8C42", ru = "хвостик" },
		{ "FinL", { -1.5, -1.5, 3.5 }, { 1.5, 2, 1 }, "FF8C42", ru = "плавничок левый" },
		{ "FinR", { -1.5, -1.5, -4.5 }, { 1.5, 2, 1 }, "FF8C42", ru = "плавничок правый" },
		{ "SpikeTop", { 0.5, 3.5, -0.5 }, { 1.5, 2, 1 }, "E0A020", ru = "шип на макушке" },
		{ "SpikeTop2", { -2.5, 3.5, -0.5 }, { 1.5, 1, 1 }, "E0A020", ru = "шип на спине" },
		{ "SpikeBottom", { 0.5, -5, -0.5 }, { 1.5, 1.5, 1 }, "E0A020", ru = "шип снизу" },
		{ "SpikeSideL", { -3, 1.5, 3.5 }, { 1.5, 1.5, 2 }, "E0A020", ru = "шип сбоку левый" },
		{ "SpikeSideR", { -3, 1.5, -5.5 }, { 1.5, 1.5, 2 }, "E0A020", ru = "шип сбоку правый" },
	},
}
