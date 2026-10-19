--!strict
--[[
	TheftController — вор (Этап 4): кнопки «Украсть» у чужих витрин и всё, что видит крадущий
	(docs/stage4_design.md §1.1, §5.1, §6.4 rev. 3; виджеты — HUD.TheftBar и HUD.TheftTitle,
	tools/builder/gui/Steal.luau; числа — UIConfig.Theft, тексты и значки — StealConfig.Texts).
	Сервер решает всё (StealService); клиент только показывает и гасит кольцо кнопки.

	Что делает:
	  • Кнопки «Украсть» — помощник TheftPrompts: прячет те, что красть нельзя, МЕСТНЫМ
	    MaxActivationDistance = 0 (сервер это свойство не пишет — его записи кнопку не вернут,
	    BE-14), по строкам Shared/TheftChecks с Client = true; кнопку, которую держишь, — никогда.
	  • Полоса вора HUD.TheftBar — в НИЖНЕЙ полосе (§6.4 rev. 3: с камеры вора витрина, которую он
	    грабит, — в верхней середине экрана, где плашки статуса и уведомления), по центру, между
	    джойстиком и кнопкой прыжка (≥ Theft.Bar.Gap px от них и от края; не шире Theft.Width
	    экрана и WidthMax px; верх — Bar.Top высоты HUD). Её виды:
	      удержание — StealEvent "Hold": тёмная плашка (Night), 🥷 «КРАДЁШЬ: ОКУНЬ», «Не отходи!»,
	        полоса заполняется к серверному концу End (один линейный твин, без покадровой
	        работы), «1,8 с» (цепочка task.delay Bar.HoldTick);
	      вынос — "Carry": красная (Berry), 🏃 «БЕГИ ЗА ОГРАДУ!», «Не попадись хозяину», полоса
	        тает к End выноса, «21 с» (Bar.CarryTick); пока собака держит (атрибут Slowed) —
	        «🐕 СОБАКА!» над правым краем; красная дорожка (Beam «TheftGuide», рецепт луча
	        рыбалки) от вора к ближайшему выходу StealRules.NearestExit (раз в BeamEvery с);
	      срыв — "Cancel": красная, трясётся, 💨 «СОРВАЛОСЬ!» и одна строка причины (Text
	        сервера), FailTime с; в удержании гасит кольцо своей кнопки (InputHoldEnd: сервер
	        кнопки не выключает — BE-15);
	      подсказка на стекле (Line, две ровные строки, ширина — по тексту, как у подсказки
	        рыбалки) — во дворе чужой базы (цепочка task.delay HintEvery, только пока есть
	        персонаж; StealRules.InPlot): почему здесь красть нельзя — пока стоишь во дворе, с
	        живым «0:24» (⏳ ожидание, 🛡️ защита, 🐠 рыба: строки TheftChecks — базы, иначе
	        витрин); можно — один раз за вход «Начнёшь красть — твоя защита погаснет» (своя база
	        под защитой) или один раз за игру «Зажми «Украсть» у витрины…» (тач) / «Держи E…»;
	        отказ сервера "Denied" — его текст на DeniedHint с (Quiet — без текста), и кольцо
	        названной кнопки гаснет (InputHoldEnd по BaseIndex / Slot); нет ни "Hold", ни
	        "Denied" за StealConfig.Hold.NoReply с после своего начала удержания — кольцо
	        гаснет, «Подожди секунду» (BE-16).
	  • «ДОБЫЧА!» — "Done": полоса уходит, HUD.TheftTitle в той же нижней полосе: огромное
	    «ДОБЫЧА!» (Gold → Leaf) ударом, «Окунь — в твоём садке · +$4/с», арпеджио редкости,
	    конфетти из точки над головой вора, 🐟 летит оттуда в «САДОК»; на прилёте снят атрибут HUD
	    TankIncoming — «САДОК» играет прилёт (TankButtonController: фишка «4/6 → 5/6», «ЗАМЕНА!» и
	    монеты, если садок был полон); через DoneTime с всё уходит.
	  • Атрибуты HUD: Stealing = фаза (как Player.Stealing сервера: "hold" | "carry"; по нему
	    HudController прячет HUD.Status и запирает «ДОМОЙ», FishingController прячет подсказку,
	    луч к кругу и кнопку действия); TankIncoming = редкость краденой рыбы с начала выноса до
	    прилёта 🐟 (снят и при срыве; кража кончилась без "Done" / "Cancel" — через
	    Bar.SafetyWait).
	  • "Returned" без Result (вору: запись хозяина так и не легла — краденая рыба вернулась к
	    нему, §3.3 F7) — уведомление его текстом («Рыба вернулась к хозяину»); с Result — это
	    хозяину (AlertController).
	Покой — ни одного покадрового соединения: цепочки task.delay и твины; кадры — только конфетти
	и полёт 🐟 «ДОБЫЧИ!» (UiFx, кончаются сами). Анимации вида — в modeTrove, вынос (луч,
	«СОБАКА!», тикер) — в carryTrove, праздник — в celebrationTrove; соединения — на сессию
	(HUD живёт всю игру), с персонажем — в characterTrove.

	API:
	  TheftController:Start(hud)
	  TheftController.Mode() -> "none" | "hint" | "hold" | "carry" | "fail" | "done"   -- тесты
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local StealConfig = require(Config:WaitForChild("StealConfig"))
local UIConfig = require(Config:WaitForChild("UIConfig"))
local FishingRules = require(Shared:WaitForChild("FishingRules"))
local StealRules = require(Shared:WaitForChild("StealRules"))
local TankRules = require(Shared:WaitForChild("TankRules"))
local TextUtil = require(Shared:WaitForChild("TextUtil"))
local Net = require(Shared:WaitForChild("Net"))
local UiFx = require(Shared:WaitForChild("UiFx"))
local Trove = require(Shared:WaitForChild("Util"):WaitForChild("Trove"))
local FishingLayout = require(script.Parent:WaitForChild("FishingLayout"))
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))
local TheftPrompts = require(script.Parent:WaitForChild("TheftPrompts"))

local player = Players.LocalPlayer

local TEXTS = StealConfig.Texts
local BANNER = TEXTS.Banner
local ICONS = TEXTS.Icons
local SPEC = UIConfig.Theft
local BAR = SPEC.Bar
local Palette = UIConfig.Palette
-- Джойстик Roblox на тач-экране: правый край от левого края экрана, px (как у Controllers/Sheet и
-- FishingController; кнопка прыжка — FishingLayout.JUMP_SMALL / JUMP_BIG).
local STICK_SMALL, STICK_BIG = 95, 180
local BAR_MAX_HEIGHT = 84 -- потолок высоты полосы (UISizeConstraint сборщика)
local TITLE_MAX_HEIGHT = 170
local ICON_SHARE = 0.45 * 1.05 -- на сколько высот плашки кружок значка выступает влево

-- Значок подсказки по причине отказа: ожидание, защита, остальное — рыба.
local WAIT_REASONS = { cooldown = true, tagged = true, new = true, loading = true, nobase = true, busy = true }
local SHIELD_REASONS = { shield = true, join = true, newbie = true, after = true, rest = true, owner = true }

type Mode = "none" | "hint" | "hold" | "carry" | "fail" | "done"

type Theft = {
	baseIndex: number,
	slot: number,
	fishId: string,
	rarity: string,
	short: string,
	income10: number,
	holdEnd: number,
	need: number,
	carryEnd: number?,
}

type Widgets = {
	hud: ScreenGui,
	bar: Frame,
	plate: Frame,
	icon: TextLabel,
	title: TextLabel,
	sub: TextLabel,
	time: TextLabel,
	track: Frame,
	fill: Frame,
	line: TextLabel,
	dog: Frame,
	slam: Frame,
	slamTitle: TextLabel,
	slamSub: TextLabel,
}

local TheftController = {}

local w: Widgets
local mode: Mode = "none"
local theft: Theft? = nil
local modeTrove = Trove.new() -- тикеры и твины текущего вида полосы
local carryTrove = Trove.new() -- вынос: красная дорожка, «СОБАКА!»
local celebrationTrove = Trove.new() -- «ДОБЫЧА!»: конфетти, полёт 🐟, уход
local characterTrove = Trove.new() -- цепочка «вор во дворе» (живёт с персонажем)
local generation = 0 -- номер вида: отложенные шаги старого вида ничего не делают
local hintUntil = 0 -- временная подсказка (отказ, «подожди», первая) держится до (os.clock)
local hintKey: string? = nil -- что сейчас написано на стекле (подсказки не перепоказываются)
local plotBase: Model? = nil -- чужой двор, где стоит персонаж (прошлый шаг цепочки)
local firstHintShown = false
local replied = true -- на последнее своё начало удержания сервер ответил ("Hold" / "Denied")
local noReplyToken = 0
local incomingSince = 0 -- (os.clock) TankIncoming стоит с

--------------------------------------------------------------------------------
-- Мелочи
--------------------------------------------------------------------------------

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function child(parent: Instance, name: string): any
	local found = parent:WaitForChild(name, 5)
	assert(found, `[TheftController] нет {parent:GetFullName()}.{name}`)
	return found
end

local function shortOf(fishId: string, fallback: string?): string
	local def = FishingRules.GetFish(fishId)
	return if def then def.ShortName else (fallback or fishId)
end

local function smallTouch(): boolean
	local camera = Workspace.CurrentCamera
	local view = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	return math.min(view.X, view.Y) <= 500
end

-- Нижняя полоса HUD (px): слева — джойстик, справа — кнопка прыжка (тач-экран), края экрана.
local function band(): (number, number)
	local width = w.hud.AbsoluteSize.X
	local left, right = BAR.Gap, width - BAR.Gap
	if UserInputService.TouchEnabled then
		local small = smallTouch()
		local jump = if small then FishingLayout.JUMP_SMALL else FishingLayout.JUMP_BIG
		-- (+ размах тряски «СОРВАЛОСЬ!»: и трясясь, плашка не ближе Gap к джойстику и прыжку)
		local wobble = BAR.Shake * width
		left = math.max(left, (if small then STICK_SMALL else STICK_BIG) + BAR.Gap + wobble)
		right = math.min(right, width - jump.right - jump.size - BAR.Gap - wobble)
	end
	return left, right
end

-- Полоса вора на месте: ширина want (nil — полная), высота — BarHeight экрана; в px HUD,
-- записано долями (UDim2.fromScale): по центру экрана, а не влезает — сдвинута в полосу.
local function placeBar(want: number?)
	local size = w.hud.AbsoluteSize
	if size.X < 2 or size.Y < 2 then
		return
	end
	local height = math.min(SPEC.BarHeight * size.Y, BAR_MAX_HEIGHT)
	local overhang = ICON_SHARE * height
	local left, right = band()
	left += overhang
	local full = math.min(SPEC.Width * size.X, SPEC.WidthMax)
	local width = math.min(want or full, full, math.max(right - left, 0))
	local center = math.clamp(size.X / 2, left + width / 2, math.max(left + width / 2, right - width / 2))
	local top = math.min(BAR.Top * size.Y, size.Y - BAR.Gap - height)
	w.bar.AnchorPoint = Vector2.new(0.5, 0)
	w.bar.Position = UDim2.fromScale(center / size.X, top / size.Y)
	w.bar.Size = UDim2.fromScale(width / size.X, height / size.Y)
end

-- «ДОБЫЧА!» — в той же нижней полосе, во всю её ширину (не шире полосы вора).
local function placeSlam()
	local size = w.hud.AbsoluteSize
	if size.X < 2 or size.Y < 2 then
		return
	end
	local left, right = band()
	local width = math.min(SPEC.Width * size.X, SPEC.WidthMax, math.max(right - left, 0))
	local height = math.min(BAR.TitleHeight * size.Y, TITLE_MAX_HEIGHT)
	local top = math.min(BAR.TitleTop * size.Y, size.Y - BAR.Gap - height)
	local center = math.clamp(size.X / 2, left + width / 2, math.max(left + width / 2, right - width / 2))
	w.slam.AnchorPoint = Vector2.new(0.5, 0)
	w.slam.Position = UDim2.fromScale(center / size.X, top / size.Y)
	w.slam.Size = UDim2.fromScale(width / size.X, height / size.Y)
end

-- Ширина «таблетки» подсказки под её текст (как у подсказки рыбалки: FishingLayout.hintWidth).
local function hintWidth(text: string): number
	local size = w.hud.AbsoluteSize
	local height = math.min(SPEC.BarHeight * size.Y, BAR_MAX_HEIGHT)
	local left, right = band()
	local room = math.min(SPEC.Width * size.X, SPEC.WidthMax, right - left - ICON_SHARE * height)
	local px = UiFx.textSize("Body")
	return FishingLayout.hintWidth(text, px, height, room, UiFx.textWidth(text, px), function(piece: string): number
		return UiFx.textWidth(piece, px)
	end)
end

local function setIcon(emoji: string)
	if w.icon.Text ~= emoji then
		w.icon.Text = emoji
	end
end

local function setHud(name: string, value: any)
	if w.hud:GetAttribute(name) ~= value then
		w.hud:SetAttribute(name, value)
	end
end

-- Новый вид полосы: старые тикеры и твины — прочь.
local function newMode(next: Mode): number
	modeTrove:Clean()
	generation += 1
	mode = next
	return generation
end

-- Показ и уход виджета с поколением: уход прячет его, только если за время «вдоха» его не
-- показали снова (иначе отложенное Visible = false спрятало бы новую полосу).
local shownAt: { [GuiObject]: number } = {}
local showing: { [GuiObject]: boolean } = {}

local function popShow(gui: GuiObject, opts: { [string]: any })
	shownAt[gui] = (shownAt[gui] or 0) + 1
	showing[gui] = true
	gui.Visible = true
	UiFx.popIn(gui, opts :: any)
end

local function popAway(gui: GuiObject, time: number?)
	shownAt[gui] = (shownAt[gui] or 0) + 1
	showing[gui] = false
	if not time then
		gui.Visible = false
		return
	end
	local token = shownAt[gui]
	UiFx.popOut(gui, { time = time })
	task.delay(time, function()
		if shownAt[gui] == token then
			gui.Visible = false
		end
	end)
end

local function isShown(gui: GuiObject): boolean
	return showing[gui] == true and gui.Visible
end

-- Показать полосу (если спрятана или уходит — выскакивает).
local function showBar()
	if not isShown(w.bar) then
		popShow(w.bar, { from = 0.4, time = 0.3 })
	end
end

local function hideBar(instant: boolean?)
	if instant then
		popAway(w.bar, nil) -- («ДОБЫЧА!» встаёт на её место сразу)
	elseif isShown(w.bar) then
		popAway(w.bar, 0.2)
	end
	popAway(w.dog, nil)
end

-- Что видно на плашке: подсказка (Line) или полоса кражи (Title, Sub, Time, Bar).
local subWidth = 0.66 -- (ширина подписи рядом с таймером: из сборки, Start)

local function layoutFor(hint: boolean, withBar: boolean)
	w.line.Visible = hint
	w.title.Visible = not hint
	local shadow = w.bar:FindFirstChild("TitleShadow")
	if shadow and shadow:IsA("GuiObject") then
		shadow.Visible = not hint
	end
	w.sub.Visible = not hint
	-- (без таймера — «СОРВАЛОСЬ!» с причиной — подпись во всю ширину заголовка)
	local wide = if withBar then subWidth else w.title.Size.X.Scale
	if w.sub.Size.X.Scale ~= wide then
		w.sub.Size = UDim2.new(wide, 0, w.sub.Size.Y.Scale, w.sub.Size.Y.Offset)
	end
	w.time.Visible = not hint and withBar
	local holder = w.fill.Parent :: GuiObject
	holder.Visible = not hint and withBar
	if hint then
		popAway(w.dog, nil)
	end
end

-- Тикер «1,8 с» / «21 с» до серверного конца endT — цепочка task.delay, пока вид тот же.
local function tickTime(token: number, endT: number, every: number, whole: boolean)
	local function step()
		if token ~= generation then
			return
		end
		local left = math.max(0, endT - serverNow())
		local s = if whole then string.format("%d", math.ceil(left - 1e-6)) else StealRules.FormatSeconds(left)
		w.time.Text = TextUtil.fill(BANNER.Time, { s = s })
		if left > 0 then
			task.delay(every, step)
		end
	end
	step()
end

-- Полоса к серверному концу: from → to (доля) за оставшееся время, один линейный твин.
local function runFill(endT: number, total: number, filling: boolean)
	local left = math.max(0, endT - serverNow())
	local k = if total > 0 then math.clamp(1 - left / total, 0, 1) else 1
	local from = if filling then k else 1 - k
	w.fill.Size = UDim2.fromScale(from, 1)
	local tween = UiFx.tween(
		w.fill,
		math.max(left, 0.01),
		{ Size = UDim2.fromScale(if filling then 1 else 0, 1) },
		Enum.EasingStyle.Linear,
		Enum.EasingDirection.InOut
	)
	modeTrove:Add(function()
		tween:Cancel()
	end)
end

local function heldPrompt(): ProximityPrompt?
	local t = theft
	return if t then TheftPrompts.PromptAt(t.baseIndex, t.slot) else nil
end

-- Погасить кольцо своей кнопки (её удержание ведёт клиент Roblox).
local function endHold(prompt: ProximityPrompt?)
	if prompt then
		pcall(function()
			prompt:InputHoldEnd()
		end)
	end
end

local function releaseIncoming()
	setHud("TankIncoming", nil)
end

--------------------------------------------------------------------------------
-- Подсказка на стекле
--------------------------------------------------------------------------------

local function iconFor(reason: string?): string
	if reason and WAIT_REASONS[reason] then
		return ICONS.Wait
	elseif reason and SHIELD_REASONS[reason] then
		return ICONS.Shield
	elseif reason == "stealing" then
		return ICONS.Hold
	end
	return ICONS.Fish
end

-- Подсказка на стекле; for_ — сколько секунд держать (nil — пока её не сменит цепочка двора).
local function showHint(text: string, emoji: string, forSeconds: number?, key: string?)
	if mode ~= "none" and mode ~= "hint" then
		return
	end
	local same = mode == "hint" and hintKey == key and key ~= nil
	if mode ~= "hint" then
		newMode("hint")
	end
	hintKey = key
	hintUntil = if forSeconds then os.clock() + forSeconds else 0
	UiFx.setCandy(w.plate, "Glass")
	layoutFor(true, false)
	setIcon(emoji)
	w.line.Text = text
	placeBar(hintWidth(text))
	if not isShown(w.bar) then
		showBar()
	elseif not same then
		UiFx.punch(w.line, { from = 0.85, peak = 1.06 })
	end
end

local function hideHint()
	if mode == "hint" then
		newMode("none")
		hintKey = nil
		hideBar()
	end
end

-- Чужой двор, где стоит персонаж (база с хозяином, не своя), или nil.
local function foreignPlot(root: BasePart): Model?
	local folder = Workspace:FindFirstChild("Bases")
	if not folder then
		return nil
	end
	local own = player:GetAttribute("BaseIndex")
	for _, base in folder:GetChildren() do
		if base:IsA("Model") and base:GetAttribute("BaseIndex") ~= own then
			local owner = base:GetAttribute("OwnerUserId")
			if type(owner) == "number" and owner > 0 and owner ~= player.UserId then
				if StealRules.InPlot(StealRules.LocalOf(base:GetPivot(), root.Position), 0) then
					return base
				end
			end
		end
	end
	return nil
end

-- Своя база под защитой сейчас (любой вид).
local function ownProtected(): boolean
	local folder = Workspace:FindFirstChild("Bases")
	local index = player:GetAttribute("BaseIndex")
	local base = folder and type(index) == "number" and folder:FindFirstChild(`Base_{index}`)
	local untilT = base and base:GetAttribute("ProtectUntil")
	return finite(untilT) and (untilT :: number) > serverNow()
end

-- Шаг цепочки «вор во дворе»: что написать на стекле (или убрать подсказку).
local function plotStep(root: BasePart)
	local base = foreignPlot(root)
	local entered = base ~= nil and base ~= plotBase
	plotBase = base
	if mode ~= "none" and mode ~= "hint" then
		return -- (кража, срыв, «ДОБЫЧА!» — у них своя полоса)
	end
	if mode == "hint" and hintUntil > os.clock() then
		return -- (отказ, «подожди», первая подсказка — держатся своё время)
	end
	if not base then
		hideHint()
		return
	end
	local reason, left = TheftPrompts.BaseReason(base)
	if reason == "self" then
		hideHint()
		return
	end
	if not reason and TheftPrompts.Shown(base) == 0 then
		reason, left = TheftPrompts.FishReason(base)
	end
	if reason then
		-- Почему здесь нельзя — пока стоишь во дворе, с живым «0:24».
		showHint(StealRules.DeniedText(reason, left), iconFor(reason), nil, `why:{reason}`)
		return
	end
	if TheftPrompts.Shown(base) == 0 then
		hideHint()
		return
	end
	if entered and ownProtected() then
		showHint(TEXTS.Hint.Protected, ICONS.Shield, BAR.HintTime, "protected")
	elseif entered and not firstHintShown then
		firstHintShown = true
		local text = if UserInputService.TouchEnabled then TEXTS.Hint.Touch else TEXTS.Hint.Keyboard
		showHint(text, ICONS.Hint, BAR.HintTime, "first")
	elseif mode == "hint" and hintUntil <= os.clock() then
		hideHint()
	end
end

local function startPlotChain(character: Model)
	characterTrove:Clean()
	plotBase = nil
	local alive = true
	characterTrove:Add(function()
		alive = false
	end)
	local function step()
		if not alive or character.Parent == nil then
			return
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			plotStep(root)
		end
		task.delay(SPEC.HintEvery, step)
	end
	task.defer(step)
end

--------------------------------------------------------------------------------
-- Удержание и вынос
--------------------------------------------------------------------------------

local function enterHold(data: { [string]: any })
	local fishId = if type(data.FishId) == "string" then data.FishId else "Perch"
	local endT = if finite(data.End) then data.End else serverNow()
	local need = if finite(data.Need) then data.Need else StealRules.HoldTime(0)
	theft = {
		baseIndex = if finite(data.BaseIndex) then data.BaseIndex else 0,
		slot = if finite(data.Slot) then data.Slot else 0,
		fishId = fishId,
		rarity = if type(data.Rarity) == "string" then data.Rarity else "Common",
		short = shortOf(fishId, if type(data.Short) == "string" then data.Short else nil),
		income10 = if finite(data.Income10) then data.Income10 else 0,
		holdEnd = endT,
		need = need,
	}
	celebrationTrove:Clean()
	popAway(w.slam, nil)
	carryTrove:Clean()
	local token = newMode("hold")
	hintKey = nil
	UiFx.setCandy(w.plate, "Night")
	UiFx.setCandy(w.fill, "Berry")
	layoutFor(false, true)
	setIcon(ICONS.Hold)
	local t = theft :: Theft
	w.title.Text = TextUtil.fill(BANNER.Hold, { short = TextUtil.upper(t.short) })
	w.sub.Text = BANNER.HoldSub
	placeBar(nil)
	showBar()
	UiFx.punch(w.title, { from = 0.8, peak = 1.08 })
	runFill(endT, need, true)
	tickTime(token, endT, BAR.HoldTick, false)
end

-- Красная дорожка от вора к ближайшему выходу с участка (пересчёт раз в BeamEvery с).
local function startGuide()
	local t = theft
	local folder = Workspace:FindFirstChild("Bases")
	local base = t and folder and folder:FindFirstChild(`Base_{t.baseIndex}`)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (base and base:IsA("Model") and root and root:IsA("BasePart")) then
		return
	end
	local from = Instance.new("Attachment")
	from.Name = "TheftGuideFrom"
	from.Position = Vector3.new(0, -2, 0)
	from.Parent = root
	local to = Instance.new("Attachment")
	to.Name = "TheftGuideTo"
	to.Parent = Workspace.Terrain
	local beam = Instance.new("Beam")
	beam.Name = "TheftGuide"
	beam.Attachment0 = from
	beam.Attachment1 = to
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Width0 = SPEC.BeamWidth[1]
	beam.Width1 = SPEC.BeamWidth[2]
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new(Palette.Berry.Top, Palette.Berry.Bottom)
	beam.Transparency = NumberSequence.new(0.35, 0.05)
	beam.Parent = root
	carryTrove:Add(beam)
	carryTrove:Add(from)
	carryTrove:Add(to)
	local alive = true
	carryTrove:Add(function()
		alive = false
	end)
	local function aim()
		if not alive or root.Parent == nil then
			return
		end
		local pivot = base:GetPivot()
		local here = StealRules.LocalOf(pivot, root.Position)
		local exit = StealRules.NearestExit(here)
		to.Position = pivot * Vector3.new(exit.X, 0.3, exit.Z)
		task.delay(SPEC.BeamEvery, aim)
	end
	aim()
end

-- «🐕 СОБАКА!» над правым краем, пока собака держит вора (атрибут Slowed).
local function watchDog()
	local function update()
		local slowed = player:GetAttribute("Slowed") == true and mode == "carry"
		if slowed and not isShown(w.dog) then
			popShow(w.dog, { from = 0.3, time = 0.3, rotate = -12 })
			UiFx.shake(w.bar, BAR.Shake * 0.5, 0.25)
		elseif not slowed and isShown(w.dog) then
			popAway(w.dog, 0.18)
		end
	end
	carryTrove:Add(player:GetAttributeChangedSignal("Slowed"):Connect(update))
	carryTrove:Add(function()
		popAway(w.dog, nil)
	end)
	update()
end

local function enterCarry(data: { [string]: any })
	local t = theft
	if not t then
		return
	end
	local endT = if finite(data.End) then data.End else serverNow() + StealConfig.Carry.Timeout
	t.carryEnd = endT
	endHold(heldPrompt()) -- (удержание кончилось: кольцо больше не нужно)
	local token = newMode("carry")
	UiFx.setCandy(w.plate, "Berry")
	UiFx.setCandy(w.fill, "Gold")
	layoutFor(false, true)
	setIcon(ICONS.Carry)
	w.title.Text = BANNER.Carry
	w.sub.Text = BANNER.CarrySub
	placeBar(nil)
	showBar()
	UiFx.rimFlash(w.plate)
	UiFx.punch(w.title, { from = 0.7, peak = 1.12 })
	runFill(endT, StealConfig.Carry.Timeout, false)
	tickTime(token, endT, BAR.CarryTick, true)
	incomingSince = os.clock()
	setHud("TankIncoming", t.rarity)
	carryTrove:Clean()
	startGuide()
	watchDog()
end

local function enterFail(data: { [string]: any })
	if data.Phase == "hold" then
		endHold(heldPrompt()) -- (сервер кнопку не выключает: так щит или касание гасят кольцо)
	end
	carryTrove:Clean()
	releaseIncoming()
	theft = nil
	local token = newMode("fail")
	UiFx.setCandy(w.plate, "Berry")
	layoutFor(false, false)
	setIcon(ICONS.Fail)
	w.title.Text = BANNER.Fail
	w.sub.Text = if type(data.Text) == "string" and data.Text ~= "" then data.Text else TEXTS.Cancel.busy
	placeBar(nil)
	showBar()
	UiFx.punch(w.title, { from = 1.3, peak = 1.1 })
	UiFx.shake(w.bar, BAR.Shake, 0.4)
	UiFx.sound("swoosh", 0.35, 0.7)
	task.delay(SPEC.FailTime, function()
		if token == generation then
			newMode("none")
			hideBar()
		end
	end)
end

-- Точка над головой вора на экране (px HUD) — оттуда конфетти и 🐟; nil — не видно.
local function headPoint(): Vector2?
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local fish = character and character:FindFirstChild("StolenFish")
	local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	local world: Vector3? = nil
	if fish and fish:IsA("Model") then
		world = fish:GetPivot().Position
	elseif head and head:IsA("BasePart") then
		world = head.Position + Vector3.new(0, 2.5, 0)
	end
	if not camera or not world then
		return nil
	end
	local point, onScreen = camera:WorldToScreenPoint(world :: Vector3)
	if not onScreen or point.Z <= 0 or not finite(point.X) or not finite(point.Y) then
		return nil
	end
	local size = w.hud.AbsoluteSize
	local at = Vector2.new(point.X, point.Y) - w.hud.AbsolutePosition
	return Vector2.new(math.clamp(at.X, size.X * 0.08, size.X * 0.92), math.clamp(at.Y, size.Y * 0.1, size.Y * 0.85))
end

local function enterDone(data: { [string]: any })
	local t = theft
	local fish: { [string]: any } = if type(data.Fish) == "table" then data.Fish :: any else {}
	local fishId = if type(fish.Id) == "string" then fish.Id elseif t then t.fishId else "Perch"
	local rarity = if type(fish.Rarity) == "string" then fish.Rarity elseif t then t.rarity else "Common"
	local income10 = if t then t.income10 elseif finite(fish.Income) then TankRules.Income10(fish.Income) else 0
	carryTrove:Clean()
	theft = nil
	local origin = headPoint()
	local token = newMode("done")
	hideBar(true)
	celebrationTrove:Clean()
	setHud("TankIncoming", rarity) -- (держит прилёт «САДОК», пока 🐟 летит)
	-- «ДОБЫЧА!» — ударом в нижней полосе, подпись — следом.
	placeSlam()
	w.slamSub.Text = TextUtil.fill(BANNER.DoneSub, {
		short = shortOf(fishId, nil),
		rate = TankRules.FormatRate(income10),
	})
	shownAt[w.slam] = (shownAt[w.slam] or 0) + 1
	showing[w.slam] = true
	w.slam.Visible = true
	UiFx.slam(w.slamTitle, 2.2, 0.35)
	UiFx.popIn(w.slamSub, { from = 0.3, time = 0.3, delay = 0.2 })
	celebrationTrove:Add(UiFx.arpeggio(rarity, 0.5))
	local size = w.hud.AbsoluteSize
	local at = origin or Vector2.new(size.X * 0.5, size.Y * 0.4)
	local style = UIConfig.Rarity[rarity] or UIConfig.Rarity.Common
	celebrationTrove:Add(UiFx.confetti(w.hud, {
		count = BAR.Confetti,
		colors = style.Confetti,
		origin = Vector2.new(at.X / math.max(size.X, 1), at.Y / math.max(size.Y, 1)),
		spread = 150,
		power = 1,
	}))
	-- 🐟 с головы — в «САДОК» (кнопки нет — прилёт сразу).
	local right = w.hud:FindFirstChild("RightButtons")
	local target = right and right:FindFirstChild("TankButton")
	if target and target:IsA("GuiObject") and target.Visible and (right :: GuiObject).Visible then
		local start = Instance.new("Frame")
		start.Name = "FxFlyFrom"
		start.BackgroundTransparency = 1
		start.AnchorPoint = Vector2.new(0.5, 0.5)
		start.Size = UDim2.fromOffset(2, 2)
		start.Position = UDim2.fromOffset(math.round(at.X), math.round(at.Y))
		start.Parent = w.hud
		celebrationTrove:Add(UiFx.flyTo(w.hud, start, target, {
			text = ICONS.Fly,
			time = BAR.FlyTime,
			size = BAR.FlySize,
			arc = 0.18,
			onArrive = function()
				releaseIncoming()
				UiFx.sound("pop", 0.35, 1.2)
			end,
		}))
		start:Destroy()
	else
		releaseIncoming()
	end
	task.delay(SPEC.DoneTime, function()
		if token == generation then
			newMode("none")
			if isShown(w.slam) then
				popAway(w.slam, 0.25)
			end
			releaseIncoming() -- (подстраховка: полёт не долетел)
		end
	end)
end

--------------------------------------------------------------------------------
-- События сервера и свои удержания
--------------------------------------------------------------------------------

local function onDenied(data: { [string]: any })
	replied = true
	noReplyToken += 1
	endHold(TheftPrompts.PromptAt(data.BaseIndex, data.Slot))
	if data.Quiet == true or mode ~= "none" and mode ~= "hint" then
		return
	end
	local text = if type(data.Text) == "string" and data.Text ~= "" then data.Text else nil
	if text then
		showHint(text, iconFor(if type(data.Reason) == "string" then data.Reason else nil), SPEC.DeniedHint, nil)
	end
end

local function onStealEvent(kind: any, data: any)
	local d: { [string]: any } = if type(data) == "table" then data else {}
	if kind == "Hold" then
		replied = true
		noReplyToken += 1
		enterHold(d)
	elseif kind == "Carry" then
		enterCarry(d)
	elseif kind == "Cancel" then
		enterFail(d)
	elseif kind == "Done" then
		enterDone(d)
	elseif kind == "Denied" then
		onDenied(d)
	elseif kind == "Returned" and d.Result == nil and type(d.Text) == "string" then
		NotifyController.Show(d.Text, "warning", { icon = ICONS.Fly })
	end
end

-- Своё начало удержания «Украсть»: эта кнопка не прячется; нет ответа за NoReply с — гасим.
local function onHoldBegan(prompt: ProximityPrompt)
	if not TheftPrompts.IsSteal(prompt) then
		return
	end
	TheftPrompts.SetHeld(prompt)
	replied = false
	noReplyToken += 1
	local token = noReplyToken
	task.delay(StealConfig.Hold.NoReply, function()
		if token ~= noReplyToken or replied then
			return
		end
		endHold(prompt)
		TheftPrompts.SetHeld(nil)
		showHint(BANNER.NoReply, ICONS.Wait, SPEC.DeniedHint, nil)
	end)
end

local function onHoldEnded(prompt: ProximityPrompt)
	if not TheftPrompts.IsSteal(prompt) then
		return
	end
	noReplyToken += 1 -- (отпустил сам — «нет ответа» уже не про него)
	TheftPrompts.SetHeld(nil)
end

-- Фаза сервера (Player.Stealing) → HUD.Stealing; кража кончилась без "Done" / "Cancel"
-- (вор ушёл со стороны клиента не бывает, но подстраховка) — прилёт «САДОК» отпускается.
local function onStealing()
	local phase = player:GetAttribute("Stealing")
	setHud("Stealing", if phase == "hold" or phase == "carry" then phase else nil)
	if phase == nil then
		local since = incomingSince
		task.delay(BAR.SafetyWait, function()
			if mode ~= "done" and incomingSince == since and player:GetAttribute("Stealing") == nil then
				releaseIncoming()
			end
		end)
		if mode == "hold" or mode == "carry" then
			-- (ни "Cancel", ни "Done" не пришли: молча убрать полосу)
			local token = generation
			task.delay(BAR.SafetyWait, function()
				if token == generation and (mode == "hold" or mode == "carry") then
					carryTrove:Clean()
					theft = nil
					newMode("none")
					hideBar()
				end
			end)
		end
	end
end

--------------------------------------------------------------------------------
-- Запуск
--------------------------------------------------------------------------------

function TheftController.Mode(): Mode
	return mode
end

function TheftController:Start(hud: ScreenGui)
	local bar = child(hud, "TheftBar")
	local slam = child(hud, "TheftTitle")
	local barHolder = child(bar, "Bar")
	w = {
		hud = hud,
		bar = bar,
		plate = child(bar, "Plate"),
		icon = child(child(bar, "Icon"), "Icon"),
		title = child(bar, "Title"),
		sub = child(bar, "Sub"),
		time = child(bar, "Time"),
		track = child(barHolder, "Track"),
		fill = child(barHolder, "Fill"),
		line = child(bar, "Line"),
		dog = child(bar, "DogChip"),
		slam = slam,
		slamTitle = child(slam, "Title"),
		slamSub = child(slam, "Sub"),
	}
	bar.Visible = false
	slam.Visible = false
	w.dog.Visible = false
	subWidth = w.sub.Size.X.Scale

	TheftPrompts.Start()

	Net.Event("StealEvent").OnClientEvent:Connect(onStealEvent)
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt: ProximityPrompt, who: Player?)
		if who == nil or who == player then
			onHoldBegan(prompt)
		end
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt: ProximityPrompt, who: Player?)
		if who == nil or who == player then
			onHoldEnded(prompt)
		end
	end)
	player:GetAttributeChangedSignal("Stealing"):Connect(onStealing)
	onStealing()

	-- Экран поменял размер — полоса и «ДОБЫЧА!» встают на место.
	hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if w.bar.Visible then
			if mode == "hint" then
				placeBar(hintWidth(w.line.Text))
			else
				placeBar(nil)
			end
		end
		if w.slam.Visible then
			placeSlam()
		end
	end)

	-- Цепочка «вор во дворе» живёт с персонажем.
	player.CharacterAdded:Connect(startPlotChain)
	player.CharacterRemoving:Connect(function()
		characterTrove:Clean()
		plotBase = nil
	end)
	if player.Character then
		startPlotChain(player.Character)
	end
end

return TheftController
