--[[
	Palette — the one colour table of the map (art direction v4, DESIGN.md §1).

	The look: a sunny, rich but natural voxel island — think a well-kept fishing village, not a
	candy shop. Lawns, soil, wood, stone, sand and water carry the picture in calm, earthy,
	medium-saturated colours; strong colour is reserved for small accents (flowers, flags, trims,
	awnings, lanterns) and for each base's own colour, used sparingly on its plot.

	Rules (checked by tools/preview/palette_lint.py on the exported map):
	  * Large surfaces (ground, walls, roofs, decks, paving, water): saturation <= 0.6 and value
	    <= 0.88 in HSV. No pure hues, no pure white or black.
	  * Strong accents (saturation up to ~0.75) only on small parts.
	  * One building = one wall colour + one roof colour + one trim colour (+ wood / stone).
	  * Neon only for lamp cores, glowing crystals and the like — small and few.
	  * No people, no animals standing around as decoration (the base dog is a gameplay upgrade).
	Lighting (tools/build.luau): warm sun, neutral-warm shadow fill, light haze, a gentle +0.1
	saturation in the grading and a light bloom only for Neon.
]]

local U = require("./Util")
local rgb = U.rgb

local P: { [string]: any } = {
	-- ground (Ground.luau uses the same values)
	GrassTop = rgb(116, 188, 72),
	GrassTop2 = rgb(102, 172, 64),
	GrassTop3 = rgb(136, 200, 88),
	Dirt = rgb(160, 112, 74),
	DirtDark = rgb(128, 88, 60),
	Sand = rgb(224, 202, 150),
	SandDark = rgb(212, 186, 134),
	SandWet = rgb(220, 196, 146),
	-- warm sandstone-like stone (neutral greys read as unpainted default parts)
	Stone = rgb(160, 148, 130),
	StoneDark = rgb(122, 110, 98),
	StoneLight = rgb(214, 202, 178),
	-- cool slate: mountains and cliffs only (recedes behind the warm village)
	Slate = rgb(132, 144, 180),
	SlateDark = rgb(112, 122, 160),
	SlateLight = rgb(160, 172, 204),
	Snow = rgb(238, 242, 246),

	-- wood and building materials
	Wood = rgb(176, 122, 78),
	WoodDark = rgb(150, 104, 70),
	WoodLight = rgb(206, 162, 112),
	Plank = rgb(194, 150, 104), -- decks, piers, boardwalks
	Plaster = rgb(228, 216, 194), -- house walls
	PlasterShade = rgb(214, 200, 176),
	Brick = rgb(172, 92, 70),
	Cobble = rgb(196, 174, 140), -- paving
	CobbleDark = rgb(156, 132, 106),
	Flagstone = rgb(210, 184, 142), -- two-tone flag paving
	FlagstoneDark = rgb(196, 168, 128),
	Limestone = rgb(222, 208, 178), -- cream stone: plinths, steps, kerbs
	RoofRed = rgb(178, 74, 60),
	RoofTerracotta = rgb(190, 100, 66),
	RoofBlue = rgb(72, 104, 150),
	RoofGreen = rgb(76, 128, 84),
	RoofSlate = rgb(96, 108, 132),
	RoofBrown = rgb(146, 100, 68),

	-- foliage: natural greens a step darker than the lawns
	Leaf0 = rgb(62, 136, 60),
	Leaf1 = rgb(76, 152, 66),
	Leaf2 = rgb(94, 168, 74),
	Leaf3 = rgb(112, 180, 84),
	LeafLight = rgb(138, 190, 96),
	Mint1 = rgb(56, 140, 96),
	Mint2 = rgb(80, 162, 110),
	Mint3 = rgb(130, 190, 140),
	BirchLeaf1 = rgb(72, 146, 68),
	BirchLeaf2 = rgb(100, 170, 80),
	BirchLeaf3 = rgb(140, 192, 104),
	Pine0 = rgb(56, 128, 80),
	Pine1 = rgb(56, 130, 78),
	Pine2 = rgb(70, 146, 86),
	Pine3 = rgb(80, 152, 90),
	PineLight = rgb(112, 170, 110),
	Palm1 = rgb(60, 140, 70),
	Palm2 = rgb(84, 162, 76),
	Palm3 = rgb(126, 186, 96),
	-- accent foliage (a few deliberate groves only): dusty blossom pink, russet / ochre autumn
	Blossom0 = rgb(204, 124, 152),
	Blossom1 = rgb(222, 156, 180),
	Blossom2 = rgb(236, 192, 208),
	Autumn0 = rgb(194, 84, 48),
	Autumn1 = rgb(222, 124, 52),
	Autumn2 = rgb(236, 172, 72),
	Bark = rgb(140, 96, 62),
	BarkDark = rgb(108, 74, 50),
	CutWood = rgb(226, 196, 146),
	PalmBark = rgb(190, 150, 100),
	PalmBarkDark = rgb(156, 118, 80),
	Birch = rgb(236, 232, 222),
	BirchDark = rgb(70, 66, 66),
	Coconut = rgb(120, 84, 52),
	Seaweed = rgb(70, 150, 100),
	RockDark = rgb(128, 124, 122),
	RockMid = rgb(156, 152, 148),
	RockLight = rgb(186, 182, 176),
	Straw = rgb(222, 184, 92),
	StrawLight = rgb(236, 210, 140),
	Twine = rgb(168, 116, 66),

	-- accents (small parts)
	Red = rgb(204, 70, 62),
	Orange = rgb(224, 136, 62),
	Yellow = rgb(232, 190, 78),
	Lime = rgb(150, 190, 80),
	Cyan = rgb(64, 164, 172),
	Blue = rgb(68, 124, 196),
	Purple = rgb(126, 98, 180),
	Pink = rgb(214, 120, 158),
	White = rgb(242, 240, 234),
	Cream = rgb(238, 228, 206),
	Glass = rgb(170, 206, 222),
	Gold = rgb(212, 170, 88), -- brass gold: rich, not candy
	GoldLight = rgb(240, 212, 120),
	Iron = rgb(90, 98, 112),
	Navy = rgb(52, 66, 100),
	Dark = rgb(40, 40, 48),
	WindowBlue = rgb(132, 186, 222),
	Rope = rgb(214, 188, 136),
	Canvas = rgb(232, 218, 186),
	Sail = rgb(244, 240, 230),

	-- light and water
	Glow = rgb(255, 220, 140), -- lantern cores (Neon)
	LightColor = rgb(255, 210, 150), -- PointLight colour
	Flame = rgb(240, 120, 50),
	FlameCore = rgb(250, 210, 90),
	Water = rgb(56, 140, 190),
	WaterLight = rgb(130, 190, 220),
	Foam = rgb(236, 244, 248),
	Cloud = rgb(250, 251, 253),
	CloudShade = rgb(222, 234, 248),

	-- lists
	Flowers = { -- jewel tones: small parts only, they are the map's colour pops
		rgb(226, 54, 64), -- red
		rgb(248, 200, 52), -- yellow
		rgb(238, 98, 154), -- pink
		rgb(152, 88, 220), -- violet
		rgb(246, 244, 238), -- white
		rgb(244, 138, 44), -- orange
		rgb(64, 132, 234), -- blue
	},
	BoatPaint = {
		rgb(196, 72, 64), -- red
		rgb(60, 150, 156), -- teal
		rgb(66, 116, 180), -- blue
		rgb(214, 178, 96), -- yellow
		rgb(238, 236, 230), -- white
		rgb(86, 150, 86), -- green
		rgb(200, 120, 140), -- rose
	},
	Festive = { -- bunting, pennants: a warm, limited set
		rgb(200, 72, 64),
		rgb(232, 196, 84),
		rgb(240, 238, 232),
		rgb(70, 124, 196),
		rgb(224, 136, 62),
		rgb(64, 160, 168),
	},
}

return P
