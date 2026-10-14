--[[
	The UI v3 «Кирпичики» kit of the GUI builder (tools/builder/gui/Theme.luau) on its own, without
	the sim: what Theme.brick / tile / topStud / studRow / roundPlate / socket / label / icon build
	(the structure UiFx.setCandy, UiFx.setStuds and the controllers rely on), and that the brick's
	proportions come from UIConfig.Brick — the same numbers the client uses. The HUD bricks in the
	built place are checked by tests/hud_style.test.luau; the runtime recolouring by uifx.

	Run: lune run tools/run_tests.luau ui_bricks
]]

local roblox = require("@lune/roblox")

local Theme = require("../tools/builder/gui/Theme")

local Instance = roblox.Instance
local Enum = roblox.Enum
local UDim2 = roblox.UDim2

local UI = Theme.UI
local BRICK = UI.Brick
local P = UI.Palette

local function frame(): any
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(0.4, 0.1)
	return f
end

local function keyAt(gradient: any, time: number): any
	for _, key in gradient.Color.Keypoints do
		if math.abs(key.Time - time) < 1e-3 then
			return key.Value
		end
	end
	return nil
end

local tests = {}

tests["brick: studs behind the side band, a capped face, a glint, no gloss"] = function(t)
	local root = frame()
	local face = Theme.brick(root, "Sun", { studs = 4, studArea = { 0.2, 1 }, studScale = 0.8 })
	t.eq(face.Name, "Face")
	t.eq(root:GetAttribute("CandyStyle"), "brick")
	t.eq(root:GetAttribute("CandyFace"), "Face")
	t.eq(root:GetAttribute("CandyRadius"), BRICK.Radius)
	t.eq(root.BackgroundTransparency, 1, "the root draws nothing")
	local lip, studs = root.Lip, root.Studs
	t.ok(studs.ZIndex < lip.ZIndex and lip.ZIndex < face.ZIndex, "studs < side band < face")
	t.eq(lip.ZIndex, Theme.BZ.Lip)
	t.ok(Theme.BZ.Content > face.ZIndex, "content goes above the face")
	t.near(face.Size.Y.Scale, 1 - BRICK.Lip, 1e-6, "the side band is UIConfig.Brick.Lip deep")
	t.eq(lip.BackgroundColor3, P.Sun.Lip)
	t.eq(lip:FindFirstChildOfClass("UIStroke"):GetAttribute("BaseThickness"), Theme.STROKE)
	t.eq(Theme.STROKE, 4, "thick Ink outlines (2.5 px on a phone)")
	local fill = face.Fill
	t.eq(fill.Rotation, 90)
	t.eq(keyAt(fill, BRICK.CapStop), P.Sun.Top, "Top right under the cap")
	t.eq(keyAt(fill, 0), Theme.lighten(P.Sun.Top, BRICK.CapLight), "a light cap on top")
	t.eq(keyAt(fill, 1), P.Sun.Bottom)
	t.eq(face:FindFirstChild("Gloss"), nil, "no glossy band")
	t.ok(face:FindFirstChild("Spec"), "a glint")
	t.eq(face.Shine.Visible, false, "the shine overlay waits hidden")
	t.eq(#studs:GetChildren(), 4)
	for i = 1, 4 do
		local stud = studs[`Stud{i}`]
		t.eq(stud:GetAttribute("CandyStud"), "front")
		t.eq(stud.SizeConstraint, Enum.SizeConstraint.RelativeYY, "sized by the brick's height")
		t.near(stud.Size.X.Scale, BRICK.StudW * 0.8, 1e-6, "studScale")
		t.near(stud.Position.X.Scale, 0.2 + 0.8 * (i - 0.5) / 4, 1e-6, "spread over studArea")
		t.near(stud.AnchorPoint.Y, BRICK.StudShow, 1e-5, "pokes out of the top edge")
		t.eq(stud.Fill.Rotation, 0, "lit from the side")
		t.eq(stud:FindFirstChildOfClass("UIStroke"):GetAttribute("BaseThickness"), BRICK.StudStroke)
	end
	-- Counts are capped; a runtime colour becomes a clean swatch.
	local many = frame()
	Theme.brick(many, nil, { studs = 50, color = roblox.Color3.fromRGB(62, 114, 200) })
	t.eq(#many.Studs:GetChildren(), BRICK.MaxStuds)
	t.eq(many.Lip.BackgroundColor3, UI.swatchFor(roblox.Color3.fromRGB(62, 114, 200)).Lip)
end

tests["tile: smooth, a thinner side band, rounder corners; round plate and studs from above"] = function(t)
	local root = frame()
	local face = Theme.tile(root, "Leaf")
	t.eq(root:GetAttribute("CandyStyle"), "tile")
	t.eq(root:FindFirstChild("Studs"), nil, "no studs")
	t.near(face.Size.Y.Scale, 1 - BRICK.TileLip, 1e-6)
	t.eq(root:GetAttribute("CandyRadius"), BRICK.TileRadius)

	-- A row of top-down studs over a plate: 2 Frames + 2 UICorners + 1 gradient each, no stroke.
	local plate = frame()
	local row = Theme.studRow(plate, { Count = 6, Rows = 2, Area = { 0.05, 0, 0.95, 0.2 }, Token = "Night" })
	t.eq(#row:GetChildren(), 12)
	local stud = row.Stud1
	t.eq(stud:GetAttribute("CandyStud"), "top")
	t.eq(stud:FindFirstChildOfClass("UIStroke"), nil, "no outline on a top stud")
	t.ok(stud.Cap and stud.Cap.Fill, "a lit cap over the shadow disc")
	t.eq(stud.BackgroundColor3, Theme.darken(P.Night.Top, 0.35))
	local count = 0
	for _ in stud:GetDescendants() do
		count += 1
	end
	t.eq(count, 4, "cheap: corner, cap, cap corner, cap gradient")

	-- The round plate (the v4 action button): a round brick with a raised centre stud.
	local button = Instance.new("TextButton")
	local plateFace = Theme.roundPlate(button, "Sky")
	t.eq(button:GetAttribute("CandyRadius"), 0.5)
	t.eq(button:GetAttribute("CandyStyle"), "brick")
	local raised = plateFace.Stud
	t.eq(raised:GetAttribute("CandyStud"), "raised")
	t.ok(raised:FindFirstChildOfClass("UIStroke"), "the raised stud is outlined")
	t.eq(raised.Cap.Fill.Color.Keypoints[2].Value, P.Sky.Bottom)
end

tests["text and icons: Nunito Heavy, outlines by tier, upright stickers, round white sockets"] = function(t)
	local root = frame()
	t.eq(Theme.FONT.Weight, Enum.FontWeight.Heavy, "the UI font is Nunito Heavy")
	t.ok(string.find(Theme.FONT.Family, "Nunito", 1, true) ~= nil)
	local title = Theme.label(root, "Title", { Text = "РЕДКАЯ", Tier = "Title", Outline = 2 })
	t.eq(title.FontFace.Weight, Enum.FontWeight.Heavy)
	t.eq(title.Outline:GetAttribute("BaseThickness"), Theme.TIER_OUTLINE.Title, "a tier lifts a thin outline")
	local body = Theme.label(root, "Body", { Text = "Подсказка", Tier = "Body" })
	t.eq(body.Outline:GetAttribute("BaseThickness"), Theme.TIER_OUTLINE.Body, "a tiered label gets one")
	t.eq(body.TextStrokeTransparency, 1, "the UIStroke draws it, not the thin legacy stroke")
	local dark = Theme.label(root, "Dark", { Text = "F", Tier = "Small", TextStrokeTransparency = 1 })
	t.eq(dark:FindFirstChild("Outline"), nil, "dark text on a white tile stays clean")
	local none = Theme.label(root, "None", { Text = "1 кг", Tier = "Body", Outline = false })
	t.eq(none:FindFirstChild("Outline"), nil, "Outline = false is respected")
	local big = Theme.label(root, "Big", { Text = "×2", Outline = 6 })
	t.eq(big.Outline:GetAttribute("BaseThickness"), 6, "display text keeps its own outline")

	local icon = Theme.icon(root, "Icon", "🐟", { Sticker = true })
	t.eq(icon.Rotation, 0, "icons stand upright")
	t.eq(icon.TextStrokeTransparency, 1, "no Ink outline on emoji")
	t.eq(icon.Sticker.Color, UI.White, "a white sticker rim")
	t.eq(icon.Sticker.ApplyStrokeMode, Enum.ApplyStrokeMode.Contextual)
	local stamp = Theme.icon(root, "Stamp", "⭐", { Rotation = -8 })
	t.eq(stamp.Rotation, -8, "a stamp may still tilt")
	t.eq(stamp:FindFirstChild("Sticker"), nil)

	local socket = Theme.socket(root, "IconSocket", "💡")
	t.eq(socket.Icon.Rotation, 0)
	t.ok(socket.Rim and socket.Rim:FindFirstChildOfClass("UIStroke"), "an inner rim ring")
	t.eq(socket:FindFirstChildOfClass("UIStroke"):GetAttribute("BaseThickness"), Theme.STROKE)
end

tests["palette: toy-brick colours under the old token names; Ink; the PIP colour kept"] = function(t)
	for _, token in { "Sky", "Sun", "Leaf", "Berry", "Grape", "Gold", "Night", "Cream", "Slate", "Mint", "Water" } do
		local look = P[token]
		t.ok(look and look.Top and look.Bottom and look.Lip, `{token} kept`)
		-- The side band is clearly darker than the face (≈ 0.6 of its value).
		local _, _, vBottom = look.Bottom:ToHSV()
		local _, _, vLip = look.Lip:ToHSV()
		t.ok(vLip < vBottom * 0.85, `{token}: a dark side band`)
	end
	t.eq(UI.Ink, roblox.Color3.fromRGB(0x15, 0x17, 0x1C), "a neutral near-black Ink")
	t.eq(UI.Fishing.PipDone, roblox.Color3.fromRGB(64, 200, 96), "the e2e bot's pip colour")
	t.eq(UI.Fx.TextStrokeMin, 2.5)
	for id, swatch in UI.BaseSwatches do
		t.ok(swatch.Top and swatch.Bottom and swatch.Lip, `base {id}`)
	end
end

return tests
