--!strict
--[[
	TankButtonController — кнопка «САДОК» (Этап 3): HUD.RightButtons.TankButton — квадратная
	бирюзовая (Water) кнопка 🐠 «САДОК» над «ДОМОЙ», фишка «4/6» (Count) в левом верхнем углу и
	красный «!» (Badge). Стиль — tools/builder/gui/STYLE.md, числа — UIConfig.TankButton.

	Что делает:
	  • Видна, когда у игрока есть база (BaseIndex > 0) и загружены данные (DataMode "Ready" /
	    "Memory"); появляется после баннера базы (атрибут HUD IntroAt — его ставит HudController)
	    через 2 × UIConfig.Wallet.IntroGap: плашка → кошелёк → «САДОК» (popIn на своём месте;
	    Position колонки не анимируется никогда — по ней раскладывает FishingController). Нажатие —
	    UiFx.press один раз в Start → TankPanelController.Toggle() (панель строит и ведёт D).
	  • Фишка «4/6» — ТОЛЬКО из атрибутов игрока TankCount / TankSlots (Tank из "Caught" решает лишь,
	    какой прилёт играть); Cream, Gold — когда садок полон.
	  • Прилёт улова (прежний договор счётчика): FishingController ставит HUD CounterHold на
	    "Caught" и CounterIncoming = редкость при закрытии карточки; пока CounterHold — фишка
	    заморожена на числе до улова. Снят: "stored" — одометр фишки, подпрыгивание Bump
	    (RarityBump в цветах редкости), кольцо цвета редкости, 🐠 плющится и качается, тик;
	    "replaced" — фишка та же, 🐠 качается, кольцо, потом MoneyController.Celebrate(Tank.Price,
	    TankButton, { Rate = "up" }) — эта кнопка ЕДИНСТВЕННАЯ празднует замену (MoneyController лишь
	    держит сумму до этого вызова; кнопка спрятана — всё равно позвать, с from = nil) и
	    уведомление «Замена! «Меч-рыба» вместо «Карасик» +$24» (TankConfig.Texts.Replaced, Leaf 💵;
	    через ReplacedToastAfter с, MoneyController.CatchToast — когда трофей над головой ушёл);
	    "sold" — фишка «6/6» пульсирует, пока карточка на экране (UIConfig.TankButton.SoldPulse:
	    продажа связана с полным садком), на прилёте — НИЧЕГО (призрак улетел в кошелёк, сумму
	    празднует сам MoneyController).
	    Нет Tank в "Caught" (садок не принял рыбу) — фишка не меняется, кнопка лишь чуть
	    подпрыгивает. Без CounterHold (нет карточки) — тот же прилёт через ArrivalWait после
	    события / через StoredWait после роста TankCount (если "Caught" не пришёл следом: он мог
	    отстать от атрибутов на кадр).
	  • Этап 4, краденая рыба (TankEvent "Stored" — TankResult и Fish прямо в данных: тот же
	    прилёт "stored" / "replaced", с монетами за проданную слабейшую): пока у HUD атрибут
	    TankIncoming (редкость; TheftController ставит его на вынос и снимает, когда 🐟 с головы вора
	    долетела в кнопку, — docs/stage4_design.md §6.4), прилёт ждёт, фишка заморожена, нажатие
	    откроет панель после прилёта — как под CounterHold. У хозяина украли (StealEvent "Lost") —
	    красная вспышка лица и кольцо, кнопка качается «нет», фишка мигает красным
	    (UIConfig.TankButton.Lost); число катится вниз по TankCount — так кража отличается от
	    продажи (§6.8).
	  • «!» новичка: после прилёта первой рыбы за всё время (Tank.First) — UiFx.badgeBob(Badge) и
	    уведомление TankConfig.Texts.FirstFish (Water 🐠; MoneyController.CatchToast: не раньше,
	    чем трофей над головой ушёл — на планшете плашка легла бы на него); панель садка
	    открылась (HUD.TankPanel стала видна — кнопкой, кнопкой у аквариума или у ларька) —
	    UiFx.badgeHide (на сессию, без remote: First и так один раз).
	  • Нажатие во время полёта рыбы (CounterHold, карточка уже закрылась; краденая 🐟 «ДОБЫЧИ!» —
	    TankIncoming, когда кража уже кончилась) запоминается (без «нет»-качания): панель
	    откроется сразу после прилёта (OpenAfter), прокрученная к новой рыбе
	    (TankPanelController.Open(uid)); прилёта не было (кража сорвалась) — не откроется. Пока
	    кража идёт (удержание, вынос: Player.Stealing) — добычи в садке ещё нет, панель
	    открывается сразу. Нажатие во время поклёвки, мини-игры или открытой карточки улова —
	    качание «нет» (wiggle).
	  • Цвет: Water (#6FF2FF → #13B8D6) близок к Sky («ЗАБРОСИТЬ» под ней на телефоне) — проверено
	    рендером tank_button (tools/preview, сценарий tank_button): кнопку отличают квадратная
	    форма, 🐠 и подпись.
	    «Жизнь» HUD (HudController) вместо 🐟 счётчика качает 🐠 этой кнопки.
	Атрибуты, которые читает: Player — TankCount, TankSlots, DataMode, BaseIndex, FishingState; HUD
	— CounterHold, CounterIncoming, TankIncoming, IntroAt. Remote: FishingState "Caught" (Tank),
	TankEvent "Stored", StealEvent "Lost". Соединения — один раз на сессию.

	API:
	  TankButtonController:Start(hud)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local UIConfig = require(Config:WaitForChild("UIConfig"))
local TankConfig = require(Config:WaitForChild("TankConfig"))
local FishingRules = require(Shared:WaitForChild("FishingRules"))
local TankRules = require(Shared:WaitForChild("TankRules"))
local TextUtil = require(Shared:WaitForChild("TextUtil"))
local Net = require(Shared:WaitForChild("Net"))
local UiFx = require(Shared:WaitForChild("UiFx"))
local MoneyController = require(script.Parent:WaitForChild("MoneyController"))

local player = Players.LocalPlayer
local SPEC = UIConfig.TankButton
local Palette = UIConfig.Palette
local WHITE = UIConfig.White

local TankButtonController = {}

-- Что пришло с "Caught" (до прилёта рыбы в кнопку).
type Pending = {
	result: string?, -- "stored" | "replaced" | "sold" | nil (садок не принял)
	rarity: string,
	uid: string?,
	first: boolean,
	price: number,
	fishId: string,
	replaced: { [string]: any }?,
}

local function number(value: any): number
	if typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end
	return 0
end

-- Панель садка (волна D) — по договору: Toggle() / Open(uid?). Берётся при первом нажатии.
local function callPanel(method: string, arg: any)
	local module = script.Parent:FindFirstChild("TankPanelController")
	if not (module and module:IsA("ModuleScript")) then
		return
	end
	local ok, found = pcall(function(): any
		return require(module) :: any
	end)
	local fn = if ok and type(found) == "table" then found[method] else nil
	if type(fn) == "function" then
		task.spawn(fn, arg) -- (сразу, в этом же кадре; ошибка панели — красным в Output, не здесь)
	end
end

function TankButtonController:Start(hud: ScreenGui)
	local right = hud:WaitForChild("RightButtons")
	local button = right:WaitForChild("TankButton") :: GuiButton
	local icon = button:WaitForChild("Icon") :: GuiObject
	local chip = button:WaitForChild("Count") :: Frame
	local chipLabel = chip:WaitForChild("Label") :: TextLabel
	local badge = button:WaitForChild("Badge") :: GuiObject
	local fishing = hud:WaitForChild("Fishing")

	local shownCount = math.floor(number(player:GetAttribute("TankCount")))
	local shownSlots = math.floor(number(player:GetAttribute("TankSlots")))
	local full: boolean? = nil
	local pending: Pending? = nil
	local incoming: string? = nil -- редкость рыбы, что летит (CounterIncoming)
	local wantsOpen = false -- нажали во время полёта: открыть после прилёта
	local stopPulse: (() -> ())? = nil -- пульс фишки «6/6», пока на экране карточка проданной рыбы
	local onboarding = false -- «!» новичка на кнопке
	local shownOnce = false

	button.Visible = false
	badge.Visible = false

	-- Рыба ещё летит в кнопку: улов (CounterHold) или краденая с головы вора (Этап 4: TankIncoming,
	-- его ставит TheftController на вынос и снимает, когда 🐟 долетела).
	local function holding(): boolean
		return hud:GetAttribute("CounterHold") ~= nil or hud:GetAttribute("TankIncoming") ~= nil
	end

	local function chipText(count: number, slots: number): string
		return `{count}/{slots}`
	end

	-- Фишка: текст и цвет (полный садок — Gold).
	local function paintChip()
		local isFull = shownSlots > 0 and shownCount >= shownSlots
		if isFull ~= full then
			full = isFull
			UiFx.setCandy(chip, if isFull then "Gold" else "Cream")
		end
	end

	local function render()
		chipLabel.Text = chipText(shownCount, shownSlots)
		paintChip()
	end

	-- Видимость: база + данные + баннер базы уже в плашке.
	local function refreshVisible()
		local index = player:GetAttribute("BaseIndex")
		local mode = player:GetAttribute("DataMode")
		local intro = hud:GetAttribute("IntroAt")
		local want = typeof(index) == "number"
			and index > 0
			and (mode == "Ready" or mode == "Memory")
			and typeof(intro) == "number"
		if want and not button.Visible then
			if not holding() then
				shownCount = math.floor(number(player:GetAttribute("TankCount")))
				shownSlots = math.floor(number(player:GetAttribute("TankSlots")))
			end
			render()
			button.Visible = true
			local gap = UIConfig.Wallet.IntroGap
			local delay = if shownOnce then 0 else math.max(0, (intro :: number) + 2 * gap - os.clock())
			shownOnce = true
			-- Масштаб на своём месте (не Position: по колонке раскладывает FishingController);
			-- 🐠 вкручивается следом.
			UiFx.popIn(button, { from = 0.3, time = 0.4, delay = delay })
			UiFx.popIn(icon, { from = 0, time = 0.4, delay = delay + 0.12, rotate = -25 })
		elseif not want and button.Visible then
			button.Visible = false
		end
	end

	-- Прилёт рыбы: odometer фишки, подпрыгивание, кольцо в цвете редкости, 🐠 плющится и качается.
	local function arrivalJuice(rarity: string?, roll: boolean)
		local style = if rarity then UIConfig.Rarity[rarity] else nil
		UiFx.bump(button, if style then SPEC.RarityBump else SPEC.Bump, if style then 0.45 else 0.35)
		local iconScale = UiFx.scaleOf(icon)
		iconScale.Scale = SPEC.Squash
		UiFx.tween(iconScale, SPEC.SquashTime, { Scale = 1 }, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
		UiFx.wiggle(icon, 14, 3, 0.5)
		UiFx.glowRing(button, {
			color = if style then (if style.Rainbow then WHITE else style.Top) else Palette.Water.Top,
			scale = SPEC.Ring.Scale,
			thickness = SPEC.Ring.Thickness,
			time = SPEC.Ring.Time,
		})
		if roll then
			UiFx.swapText(chipLabel, chipText(shownCount, shownSlots))
			UiFx.flashText(chipLabel, if style and not style.Rainbow then style.Bottom else Palette.Water.Bottom, 0.35)
			UiFx.bump(chip, 1.25, 0.3)
		end
		UiFx.sound("tick", 0.45, 1.3)
	end

	local function openPanel(uid: string?)
		callPanel("Open", uid)
	end

	local function endPulse()
		local stop = stopPulse
		stopPulse = nil
		if stop then
			stop()
		end
	end

	-- Рыба долетела (CounterHold снят) или пришла без карточки.
	local function arrive()
		endPulse()
		local catch = pending
		pending = nil
		local rarity = incoming or (if catch then catch.rarity else nil)
		incoming = nil
		local before = shownCount
		shownCount = math.floor(number(player:GetAttribute("TankCount")))
		shownSlots = math.floor(number(player:GetAttribute("TankSlots")))
		paintChip()
		local result = if catch then catch.result else nil
		if result == "sold" then
			chipLabel.Text = chipText(shownCount, shownSlots) -- (на кнопке — ничего: монеты в кошельке)
		elseif result == "replaced" and catch then
			chipLabel.Text = chipText(shownCount, shownSlots)
			arrivalJuice(rarity, false)
			-- Монеты за проданную слабую рыбу — из «САДОК» в кошелёк (кнопка спрятана — без полёта).
			local from = if button.Visible then button else nil
			task.delay(0.18, function()
				MoneyController.Celebrate(catch.price, from, { Rate = "up" })
			end)
			local gone = catch.replaced
			local newDef = FishingRules.GetFish(catch.fishId)
			local oldDef = if gone and typeof(gone.Id) == "string" then FishingRules.GetFish(gone.Id) else nil
			-- (уведомление — когда монеты долетели и трофей над головой ушёл: не на рыбу и табличку)
			MoneyController.CatchToast(
				TextUtil.fill(TankConfig.Texts.Replaced, {
					new = if newDef then newDef.ShortName else catch.fishId,
					old = if oldDef then oldDef.ShortName elseif gone then tostring(gone.Id) else "?",
					price = TankRules.FormatMoney(catch.price),
				}),
				"success",
				{ swatch = Palette.Leaf, icon = "💵" },
				SPEC.ReplacedToastAfter
			)
		elseif result == "stored" or (catch == nil and shownCount > before) then
			-- (одометр: Label.Text — уже новое число, прежнее уезжает копией)
			chipLabel.Text = chipText(before, shownSlots)
			arrivalJuice(rarity, true)
		else
			render()
			if catch then
				UiFx.bump(button, 1.12, 0.25) -- садок не принял рыбу: фишка та же
			end
		end
		if catch and catch.first and result ~= "sold" then
			onboarding = true
			UiFx.badgeBob(badge)
			MoneyController.CatchToast(
				TankConfig.Texts.FirstFish,
				"info",
				{ swatch = Palette.Water, icon = "🐠" },
				SPEC.ToastAfter
			)
		end
		if wantsOpen then
			wantsOpen = false
			-- (ничего не прилетело — кража сорвалась: панель сама не открывается)
			if catch or shownCount > before then
				local uid = if catch and result ~= "sold" then catch.uid else nil
				task.delay(SPEC.OpenAfter, openPanel, uid)
			end
		end
	end

	-- "Caught" (Tank — что стало в садке) или TankEvent "Stored" (Этап 4: рыба легла не из
	-- улова — краденая; TankResult прямо в данных): запомнить, что за прилёт играть; пока рыба
	-- летит (CounterHold / TankIncoming) — ждать, иначе — сыграть через ArrivalWait.
	local function expect(fish: any, tank: any)
		local catch: Pending = {
			result = if tank and typeof(tank.Result) == "string" then tank.Result else nil,
			rarity = if typeof(fish.Rarity) == "string" then fish.Rarity else "Common",
			uid = if tank and typeof(tank.Uid) == "string"
				then tank.Uid
				elseif typeof(fish.Uid) == "string" then fish.Uid
				else nil,
			first = tank ~= nil and tank.First == true,
			price = math.floor(number(if tank then tank.Price else nil)),
			fishId = if typeof(fish.Id) == "string" then fish.Id else "",
			replaced = if tank and typeof(tank.Replaced) == "table" then tank.Replaced else nil,
		}
		pending = catch
		-- Продана сразу (садок полон): пока её карточка на экране, полная фишка пульсирует —
		-- ребёнок связывает «ПРОДАНА» с «6/6» (до прилёта / снятия CounterHold).
		endPulse()
		if catch.result == "sold" and button.Visible then
			stopPulse = UiFx.pulse(chip, SPEC.SoldPulse, SPEC.SoldPeriod)
		end
		-- (FishingController ставит CounterHold на этот же "Caught" — до нас или после;
		-- TheftController держит TankIncoming с начала выноса до прилёта 🐟)
		task.delay(SPEC.ArrivalWait, function()
			if pending == catch and not holding() then
				arrive()
			end
		end)
	end
	Net.Event("FishingState").OnClientEvent:Connect(function(kind: any, data: any)
		if kind == "Caught" and typeof(data) == "table" and typeof(data.Fish) == "table" then
			expect(data.Fish, if typeof(data.Tank) == "table" then data.Tank else nil)
		end
	end)
	Net.Event("TankEvent").OnClientEvent:Connect(function(kind: any, data: any)
		if kind == "Stored" and typeof(data) == "table" and typeof(data.Fish) == "table" then
			expect(data.Fish, data)
		end
	end)

	-- Этап 4: у хозяина украли рыбу (StealEvent "Lost") — «САДОК» вспыхивает красным ободком и
	-- качается «нет», фишка мигает Berry; само число катится вниз по атрибуту TankCount.
	Net.Event("StealEvent").OnClientEvent:Connect(function(kind: any)
		if kind ~= "Lost" or not button.Visible then
			return
		end
		local lost = SPEC.Lost
		UiFx.morphFlash(button, Palette.Berry.Bottom)
		UiFx.glowRing(button, {
			color = Palette.Berry.Top,
			scale = SPEC.Ring.Scale,
			thickness = SPEC.Ring.Thickness,
			time = SPEC.Ring.Time,
		})
		UiFx.wiggle(button, lost.Wiggle, lost.Swings, lost.Time)
		UiFx.flashText(chipLabel, Palette.Berry.Bottom, lost.Time)
	end)

	hud.AttributeChanged:Connect(function(name: string)
		if name == "CounterHold" or name == "TankIncoming" then
			local value = hud:GetAttribute(name)
			if name == "TankIncoming" and typeof(value) == "string" then
				incoming = value -- (прилёт в цветах редкости краденой рыбы)
			end
			if not holding() then
				arrive() -- (и без "Caught": фишка догоняет атрибуты, выросла — тот же прилёт)
			end
		elseif name == "CounterIncoming" then
			local value = hud:GetAttribute("CounterIncoming")
			if typeof(value) == "string" then
				incoming = value
			end
		elseif name == "IntroAt" then
			refreshVisible()
		end
	end)

	-- Атрибуты садка: через кадр (карточка улова успевает поставить CounterHold в том же кадре);
	-- пока CounterHold или ждём прилёта — фишка заморожена.
	local function onTankAttribute()
		if holding() or pending then
			return
		end
		local count = math.floor(number(player:GetAttribute("TankCount")))
		local slots = math.floor(number(player:GetAttribute("TankSlots")))
		if count == shownCount and slots == shownSlots then
			return
		end
		if count > shownCount and button.Visible then
			-- Рыба легла без карточки (Этап 4: "Stored") — тот же прилёт, но чуть погодя: "Caught"
			-- мог отстать от атрибутов на кадр (тогда прилёт сыграет карточка).
			task.delay(SPEC.StoredWait, function()
				if not holding() and not pending and number(player:GetAttribute("TankCount")) > shownCount then
					arrive()
				end
			end)
			return
		end
		local before = chipText(shownCount, shownSlots)
		shownCount, shownSlots = count, slots
		paintChip()
		if button.Visible and before ~= chipText(count, slots) then
			chipLabel.Text = before
			UiFx.swapText(chipLabel, chipText(count, slots))
		else
			render()
		end
	end
	player.AttributeChanged:Connect(function(name: string)
		if name == "TankCount" or name == "TankSlots" then
			task.defer(onTankAttribute)
		elseif name == "BaseIndex" or name == "DataMode" then
			refreshVisible()
		end
	end)

	-- Панель садка открылась (откуда угодно) — «!» новичка уходит.
	local tankPanel = hud:FindFirstChild("TankPanel")
	if tankPanel and tankPanel:IsA("GuiObject") then
		tankPanel:GetPropertyChangedSignal("Visible"):Connect(function()
			if tankPanel.Visible and onboarding then
				onboarding = false
				UiFx.badgeHide(badge)
			end
		end)
	end

	-- Нажатие: поклёвка, мини-игра, открытая карточка — «нет»; рыба летит — открыть после прилёта.
	local function busy(): boolean
		local state = player:GetAttribute("FishingState")
		if state == "Bite" or state == "Reeling" then
			return true
		end
		for _, name in { "CatchCard", "BiteAlert", "Minigame" } do
			local widget = fishing:FindFirstChild(name)
			if widget and widget:IsA("GuiObject") and widget.Visible then
				return true
			end
		end
		return false
	end
	UiFx.press(button, { sound = "click" })
	button.Activated:Connect(function()
		if busy() then
			UiFx.wiggle(button, 7, 2, 0.3)
			return
		end
		-- Рыба ещё летит: откроем, как долетит. Пока кража идёт (удержание, вынос) — добычи в
		-- садке ещё нет: открыть сразу (иначе панель выскочила бы сама на «СОРВАЛОСЬ!»).
		local flying = hud:GetAttribute("CounterHold") ~= nil
			or (hud:GetAttribute("TankIncoming") ~= nil and player:GetAttribute("Stealing") == nil)
		if flying then
			wantsOpen = true
			return
		end
		callPanel("Toggle", nil)
	end)

	render()
	refreshVisible()
end

return TankButtonController
