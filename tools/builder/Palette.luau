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
	Lighting (tools/build.luau) is neutral: no extra saturation in the colour grading, a light
	bloom only for Neon, so these colours are what the player sees.
]]

local U = require("./Util")
local rgb = U.rgb

local P: { [string]: any } = {
	-- ground (Ground.luau uses the same values)
	GrassTop = rgb(110, 178, 70),
	GrassTop2 = rgb(96, 162, 62),
	GrassTop3 = rgb(130, 190, 84),
	Dirt = rgb(160, 112, 74),
	DirtDark = rgb(128, 88, 60),
	Sand = rgb(232, 212, 160),
	SandDark = rgb(212, 186, 134),
	SandWet = rgb(220, 196, 146),
	Stone = rgb(150, 146, 142),
	StoneDark = rgb(118, 114, 112),
	StoneLight = rgb(182, 178, 172),
	Snow = rgb(238, 242, 246),

	-- wood and building materials
	Wood = rgb(176, 122, 78),
	WoodDark = rgb(126, 84, 54),
	WoodLight = rgb(206, 162, 112),
	Plank = rgb(194, 150, 104), -- decks, piers, boardwalks
	Plaster = rgb(236, 226, 204), -- house walls
	PlasterShade = rgb(214, 200, 176),
	Brick = rgb(172, 92, 70),
	Cobble = rgb(168, 160, 150), -- paving
	CobbleDark = rgb(138, 130, 122),
	RoofRed = rgb(178, 74, 60),
	RoofTerracotta = rgb(190, 100, 66),
	RoofBlue = rgb(72, 104, 150),
	RoofGreen = rgb(76, 128, 84),
	RoofSlate = rgb(84, 92, 110),
	RoofBrown = rgb(122, 82, 58),

	-- foliage: natural greens a step darker than the lawns
	Leaf0 = rgb(54, 122, 56),
	Leaf1 = rgb(66, 140, 62),
	Leaf2 = rgb(86, 160, 70),
	Leaf3 = rgb(112, 180, 84),
	LeafLight = rgb(138, 190, 96),
	Mint1 = rgb(56, 140, 96),
	Mint2 = rgb(80, 162, 110),
	Mint3 = rgb(130, 190, 140),
	BirchLeaf1 = rgb(72, 146, 68),
	BirchLeaf2 = rgb(100, 170, 80),
	BirchLeaf3 = rgb(140, 192, 104),
	Pine0 = rgb(38, 104, 64),
	Pine1 = rgb(46, 116, 70),
	Pine2 = rgb(58, 134, 78),
	Pine3 = rgb(80, 152, 90),
	PineLight = rgb(112, 170, 110),
	Palm1 = rgb(60, 140, 70),
	Palm2 = rgb(84, 162, 76),
	Palm3 = rgb(126, 186, 96),
	Blossom0 = rgb(214, 124, 160),
	Blossom1 = rgb(230, 156, 184),
	Blossom2 = rgb(240, 190, 210),
	Autumn0 = rgb(198, 96, 52),
	Autumn1 = rgb(218, 134, 58),
	Autumn2 = rgb(228, 170, 72),
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
	Gold = rgb(226, 178, 64),
	GoldLight = rgb(240, 212, 120),
	Iron = rgb(90, 98, 112),
	Navy = rgb(52, 66, 100),
	Dark = rgb(40, 40, 48),
	WindowBlue = rgb(88, 132, 180),
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
	CloudShade = rgb(226, 234, 244),

	-- lists
	Flowers = {
		rgb(206, 72, 72), -- red
		rgb(232, 196, 84), -- yellow
		rgb(222, 130, 166), -- pink
		rgb(146, 112, 196), -- violet
		rgb(240, 238, 232), -- white
		rgb(226, 140, 70), -- orange
		rgb(96, 140, 206), -- blue
	},
	BoatPaint = {
		rgb(196, 72, 64), -- red
		rgb(60, 150, 156), -- teal
		rgb(66, 116, 180), -- blue
		rgb(226, 186, 80), -- yellow
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
