--!strict
--[[
	Sheet — помощник «листа» (Этап 3): модальная панель HUD поверх игры — панель садка
	(TankPanelController), потом магазин Этапа 5. Модуль, не контроллер (его нет в ORDER
	ClientMain). Оболочку листа строит tools/builder/gui/Sheet.luau: корень (HUD.<Имя>, ZIndex 30,
	спрятан) → Panel (плашка) → Header (ряд шапки), Close (круглый ✕), Cards (ScrollingFrame +
	UIGridLayout). Стиль — tools/builder/gui/STYLE.md.
	ЗАГЛУШКА (волна 0): Sheet.new возвращает лист, который ничего не делает (Open — false, IsOpen —
	false). Реализация — волна 2 (scratchpad design.md, §6.1, §6.4).

	Что делает лист:
	  • Open — snapIn плашки (+ staggerPop детей Cards — делает владелец), Close — popOut.
	  • Место: в px при открытии — слева 16 px (+ безопасный отступ), справа min(RightButtons.left,
	    Jump.left) − 16, сверху низ HUD.Status + 16, снизу HUD − 16; на больших экранах — не больше
	    opts.MaxSize (900 × 560) по центру этого места; записывается как UDim2.fromScale(x / W,
	    y / H) от HUD и пересчитывается при смене ViewportSize (одно соединение на открытый лист).
	  • Сам закрывается, когда рыбалке нужен экран: FishingState игрока становится "Bite" или
	    "Reeling", у HUD появляется CounterHold, становятся видны HUD.Fishing.BiteAlert / Minigame /
	    CatchCard (opts.onClose(reason) узнаёт почему: "fishing" | "close" | "toggle" | "api").
	  • Всё, что живёт пока лист открыт, — в его Trove (закрыт — соединений как до открытия).

	API:
	  Sheet.new(hud, root, opts?) -> Sheet
	    opts = { MaxSize: Vector2?, onClose: ((reason: string) -> ())? }
	  sheet:Open() -> boolean          -- false: сейчас нельзя (рыбалка на экране)
	  sheet:Close(reason: string?)
	  sheet:IsOpen() -> boolean
	  sheet:Place()                    -- пересчитать место (смена экрана)
	  sheet:Destroy()
]]

export type Options = {
	MaxSize: Vector2?,
	onClose: ((reason: string) -> ())?,
}

export type Sheet = {
	Root: GuiObject,
	Open: (self: Sheet) -> boolean,
	Close: (self: Sheet, reason: string?) -> (),
	IsOpen: (self: Sheet) -> boolean,
	Place: (self: Sheet) -> (),
	Destroy: (self: Sheet) -> (),
}

local Sheet = {}

function Sheet.new(_hud: ScreenGui, root: GuiObject, _opts: Options?): Sheet
	local sheet: Sheet = {
		Root = root,
		Open = function(_self: Sheet): boolean
			return false
		end,
		Close = function(_self: Sheet, _reason: string?) end,
		IsOpen = function(_self: Sheet): boolean
			return false
		end,
		Place = function(_self: Sheet) end,
		Destroy = function(_self: Sheet) end,
	}
	return sheet
end

return Sheet
