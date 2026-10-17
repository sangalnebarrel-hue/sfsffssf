--[[
	Builds StarterGui.HUD — the main mobile-friendly interface (landscape; the place locks
	StarterGui.ScreenOrientation to LandscapeSensor).

	Sizing rules (phones first):
	  • everything is in Scale, never fixed pixels — except the 16 px gaps to the screen edges
	    and to the CoreGui (the Roblox hotbar is switched off since v3: HudController disables
	    the Backpack CoreGui, the rod is taken with «ВЗЯТЬ»; Theme.HOTBAR = 0);
	  • SizeConstraint RelativeYY makes widgets scale with screen HEIGHT, so they look the same
	    on a phone and on a PC; UISizeConstraint caps them on big screens;
	  • ScreenInsets = CoreUISafeInsets keeps widgets out of the notch and the Roblox top bar.

	Screen grid (H = safe-area height), planned for all stages:
	  Status        top-centre stack, two rows (it cannot grow on phones: toasts and the held
	                trophy are right under it): the base badge (St.1) and, under it, the catch
	                counter (St.2) — the Wallet (St.3: 💵 money + «+$/с» income) takes that row
	                when the counter goes; the shield timer (St.4) is a glass chip docked at the
	                right end of the badge. Top-left is the chat window, top-right the player
	                list (with «Деньги» and «Доход/с» columns from St.3) — both CoreGui.
	  Toasts        centred column from y = 0.23H, width from screen WIDTH (never reaches
	                the corners; 512 px at most without touch: clear of the chat window); one
	                toast at a time on phones, none over the catch card (or, on phones, the
	                bite / minigame) — the rest wait in a queue.
	  RightButtons  column anchored at its BOTTOM (y = 0.64H) and growing upwards, so the
	                bottom-right 0.36H stays free for the mobile Jump button (and the Stage 2
	                cast button left of it). HudController moves it lower on non-touch screens.
	                Bottom to top: Home (St.1), «САДОК» (St.3, TankButton), the third slot free
	                for St.5 (then the trophy chip needs another place on phones).
	  Fishing       (St.2) ActionArea bottom-right, LEFT of the mobile Jump button (phones: 70 px
	                at 25..95 px from the right; screens over 500 px tall: 120 px at 50..170 px);
	                the centre column — Hint, BiteAlert, Minigame (never shown together) — on one
	                bottom line 16 px above the screen bottom, between the thumbstick and the
	                action button (FishingController shifts it on narrow screens). v3, phones
	                (HUD under 500 px tall): nothing covers the own fisher (FishingLayout) — the
	                minigame docks LEFT of him, the hint and «КЛЮЁТ!» stay under his feet, the
	                catch card docks left beside the trophy, the giant rarity word goes to the
	                top band;
	                CatchCard as a modal between the status stack and the screen bottom.
	  TankPanel     (St.3) the tank sheet (gui/Sheet.luau shell + gui/Tank.luau content), ZIndex 30:
	                left 16 px .. 16 px left of the right column / Jump, 16 px under the status stack
	                .. 16 px above the bottom (capped 900 × 560 and centred on big screens); never
	                over the Wallet or «САДОК», no dim; it closes itself when the bite, the minigame
	                or the catch card needs the screen (Controllers/Sheet.luau).
	  (Stage 5)     the shop on the same sheet shell.

	Controllers that use these names: HudController, NotifyController, FishingController,
	MoneyController, TankButtonController, TankPanelController.
]]
local U = require("./Util")
local Hud = require("./gui/Hud")
local buildFishing = require("./gui/Fishing")
local buildTank = require("./gui/Tank")

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
	buildTank(hud)

	return hud
end
