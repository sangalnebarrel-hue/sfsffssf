--[[
	Builds StarterGui.HUD — the main mobile-friendly interface (landscape; the place locks
	StarterGui.ScreenOrientation to LandscapeSensor).

	Sizing rules (phones first):
	  • everything is in Scale, never fixed pixels — except HOTBAR: the fishing widgets stand
	    that many pixels above the screen bottom, because the Roblox hotbar (CoreGui, drawn over
	    PlayerGui) is a fixed-pixel band there (60 px slots, 5..65 px from the bottom, centred);
	  • SizeConstraint RelativeYY makes widgets scale with screen HEIGHT, so they look the same
	    on a phone and on a PC; UISizeConstraint caps them on big screens;
	  • ScreenInsets = CoreUISafeInsets keeps widgets out of the notch and the Roblox top bar.

	Screen grid (H = safe-area height), planned for all stages:
	  Status        top-centre stack: base badge (St.1), catch counter (St.2), money (St.3),
	                shield timer (St.4).
	                Top-left is the chat window, top-right the player list — both CoreGui.
	  Toasts        centred column from y = 0.27H, width from screen WIDTH (never reaches
	                the corners); while a fishing widget is up only its first slot shows.
	  RightButtons  column anchored at its BOTTOM (y = 0.64H) and growing upwards, so the
	                bottom-right 0.36H stays free for the mobile Jump button (and the Stage 2
	                cast button left of it). HudController moves it lower on non-touch screens.
	  Fishing       (St.2) ActionArea bottom-right, LEFT of the mobile Jump button (phones: 70 px
	                at 25..95 px from the right; screens over 500 px tall: 120 px at 50..170 px);
	                the centre column — Hint, BiteAlert, Minigame (never shown together) — on one
	                bottom line 16 px above the hotbar, between the thumbstick and the action
	                button (FishingController shifts it on narrow screens);
	                CatchCard as a modal between the status stack and the hotbar.
	  (Stage 5)     shop as a centred modal.

	Controllers that use these names: HudController, NotifyController, FishingController.
]]
local U = require("./Util")
local Hud = require("./gui/Hud")
local buildFishing = require("./gui/Fishing")

local Enum = U.Enum

return function(game: any)
	local starterGui = game:GetService("StarterGui")
	local hud = U.new("ScreenGui", {
		Name = "HUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 1,
	}, starterGui)

	Hud.buildStatus(hud)
	Hud.buildRightButtons(hud)
	buildFishing(hud)
	Hud.buildToasts(hud)

	return hud
end
