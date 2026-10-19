--!strict
--[[
	TheftController — вор (Этап 4): кнопки «Украсть» у чужих витрин и всё, что видит крадущий
	(docs/stage4_design.md §1.1, §5.1, §6.4 rev. 3, §11.6; виджеты — HUD.TheftBar и HUD.TheftTitle,
	tools/builder/gui/Steal.luau; числа — UIConfig.Theft, тексты и значки — StealConfig.Texts).
	Сервер решает всё (StealService); клиент только показывает и гасит кольцо кнопки.

	Что делает:
	  • Кнопки «Украсть» — помощник TheftPrompts: прячет те, что красть нельзя, МЕСТНЫМ
	    MaxActivationDistance = 0 (сервер это свойство не пишет — его записи кнопку не вернут,
	    BE-14), по строкам Shared/TheftChecks с Client = true; кнопку, которую держишь, — никогда.
	    База хозяина закрыта для вора ("Cancel" с BaseUntil / BaseReason: поймал — «tagged», щит
	    хозяина против этой кражи — «shielded», Limits.BaseFails срывов на ней — «wary») — её
	    кнопки спрятаны до BaseUntil (SetTagged: строка «wait» TagLeft / TagKind, как у сервера;
	    сервер без BaseUntil и «tag» — на Limits.TagCooldown с). Отказ сервера "Denied" с Until —
	    кнопки этой причины спрятаны до Until (SetDenied): ребёнок не жмёт мёртвую кнопку.
	  • Полоса вора HUD.TheftBar — в НИЖНЕЙ полосе (§6.4 rev. 3: с камеры вора витрина, которую он
	    грабит, — в верхней середине экрана, где плашки статуса и уведомления), по центру, между
	    джойстиком и кнопкой прыжка (≥ Theft.Bar.Gap px от них и от края; не шире Theft.Width
	    экрана и WidthMax px; верх — Bar.Top высоты HUD); ширина меняется твином за Bar.Resize с
	    (подсказка ↔ кража). Её виды:
	      удержание — StealEvent "Hold": тёмная плашка (Night), 🥷 «КРАДЁШЬ: ОКУНЬ», под ним
	        толстая полоса (Berry) заполняется к серверному концу End (один линейный твин, без
	        покадровой работы), в ней «Не отходи!» и «1,8 с» (цепочка task.delay Bar.HoldTick:
	        на каждой целой секунде «1,8 с» подпрыгивает, за Bar.HoldWarn с до конца ободок
	        плашки вспыхивает);
	      вынос — "Carry": красная (Berry), 🏃 «БЕГИ ЗА ОГРАДУ!», золотая полоса тает к End
	        выноса (толчок на старте), в ней «Не попадись хозяину» и «21 с» (Bar.CarryTick;
	        последние Bar.CarryWarn с — «21 с» подпрыгивает, ободок вспыхивает); нажал «ДОМОЙ» под
	        замком (атрибут HUD HomeLockedTap, HudController) — «🔒 Сначала за ограду!» вместо
	        «Не попадись хозяину» на Bar.LockedTime с; пока собака
	        держит (атрибут Slowed) — «🐕 СОБАКА!» над правым краем (качается, появляясь);
	        красная дорожка на земле (папка Workspace.TheftGuide, Theft.Guide): шевроны от
	        вора к ближайшему выходу StealRules.NearestExit ползут к нему (бегущие огни), у
	        выхода — зелёное дышащее кольцо и табличка «ВЫХОД» (TankWorldController.TrackWord:
	        у плашек HUD тает; где на экране «ГАВ!» собаки — на весь его подъём, ближе
	        Guide.Label.Clear px — ждёт, пока он не уйдёт: слова слились бы; пока «ГАВ!» живёт,
	        проверка раз в Guide.BarkEvery с); переставляется раз в BeamEvery с (task.delay);
	      срыв — "Cancel": красная, трясётся, 💨 «СОРВАЛОСЬ!» и под ним причина (Text сервера,
	        Reason: шрифт Body во всю ширину; плашка — по длине текста, в одну строку: на
	        планшете и компьютере — и шире Theft.WidthMax, но не шире полосы), FailTime с; в
	        удержании гасит кольцо своей кнопки (InputHoldEnd: сервер кнопки не выключает —
	        BE-15). Короткий тап (отпустил «Украсть» раньше Limits.QuietSavedUnder с) — не
	        срыв, а подсказка на стекле «Не отпускай «Украсть», пока полоска не заполнится!»
	        (и сервер не ждёт после него: Limits.FreeTaps раз за FailWindow);
	      подсказка на стекле (Line, две ровные строки, ширина — по тексту, как у подсказки
	        рыбалки) — во дворе чужой базы (цепочка task.delay HintEvery, только пока есть
	        персонаж; StealRules.InPlot): почему здесь красть нельзя — пока стоишь во дворе, с
	        живым «0:24» (⏳ ожидание, 🛡️ защита и база, закрытая щитом хозяина («shielded»),
	        👀 хозяин рядом и хозяин настороже («wary»), 🐠 рыба: строки TheftChecks — базы, иначе
	        витрин); можно — по очереди: «Начнёшь красть — твоя защита погаснет» (своя база под
	        защитой: раз за защиту и до первой кражи под ней — сервер гасит защиту только после
	        окна тапа, Wave 3 UX-01), потом «Зажми «Украсть» у витрины…» один раз за игру (текст —
	        по последнему вводу: тач / клавиатура / геймпад);
	        отказ сервера "Denied" — его текст на DeniedHint с (Quiet — без текста), и кольцо
	        названной кнопки гаснет (InputHoldEnd по BaseIndex / Slot); нет ни "Hold", ни
	        "Denied" за max(Hold.NoReply, пинг + Hold.NoReplySlack) с после своего начала
	        удержания — кольцо гаснет, «Подожди секунду» (BE-16); опоздавшие "Hold" / "Cancel"
	        этой кнопки (сервер начал удержание до того, как клиент сдался: End − Need) — без
	        полосы и без «СОРВАЛОСЬ!» (та же подсказка), а новое удержание той же кнопки — как
	        обычно. Пока идёт своя кража (Player.Stealing, он бывает раньше "Hold") и пока открыт
	        лист (HUD.TankPanel, HUD.DefencePanel) — подсказок двора нет.
	  • Уведомления (HUD.Toasts) ждут, пока кража идёт (своё начало удержания — и до "Cancel" /
	    "Done"): NotifyController.Reserve("thief", вся колонка) — колонка над витриной, которую
	    грабят, и над рыбой на голове (§6.4 rev. 3); ключ не из RESERVE_ORDER, поэтому тревога
	    хозяина ("alert", если обворовывают и его самого) остаётся наверху колонки.
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
	и полёт 🐟 «ДОБЫЧИ!» (UiFx, кончаются сами). Анимации вида — в modeTrove, вынос (дорожка,
	«СОБАКА!») — в carryTrove, праздник — в celebrationTrove; соединения — на сессию (HUD живёт
	всю игру), с персонажем — в characterTrove.

	API:
	  TheftController:Start(hud)
	  TheftController.Mode() -> "none" | "hint" | "hold" | "carry" | "fail" | "done"   -- тесты
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local DefenceConfig = require(Config:WaitForChild("DefenceConfig"))
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
local TankDisplay = require(script.Parent:WaitForChild("TankDisplay"))
local TankWorldController = require(script.Parent:WaitForChild("TankWorldController"))
local TheftPrompts = require(script.Parent:WaitForChild("TheftPrompts"))
local TheftWorldController = require(script.Parent:WaitForChild("TheftWorldController"))

local player = Players.LocalPlayer

local TEXTS = StealConfig.Texts
local BANNER = TEXTS.Banner
local ICONS = TEXTS.Icons
local LIMITS = StealConfig.Limits
local SPEC = UIConfig.Theft
local BAR = SPEC.Bar
local GUIDE = SPEC.Guide
local Palette = UIConfig.Palette
-- Джойстик Roblox на тач-экране: правый край от левого края экрана, px (как у Controllers/Sheet и
-- FishingController; кнопка прыжка — FishingLayout.JUMP_SMALL / JUMP_BIG).
local STICK_SMALL, STICK_BIG = 95, 180
local BAR_MAX_HEIGHT = 84 -- потолок высоты полосы (UISizeConstraint сборщика)
local TITLE_MAX_HEIGHT = 170
local ICON_SHARE = 0.45 * 1.05 -- на сколько высот плашки кружок значка выступает влево
local FAIL_PAD = 14 -- плашка «СОРВАЛОСЬ!» шире своего текста на столько px
local FAIL_SLACK = 1.08 -- … и причина — шире своей оценки по буквам во столько раз
local RESERVE_KEY = "thief" -- колонка уведомлений (не из RESERVE_ORDER: «alert» выше)
local SHEETS = { "TankPanel", "DefencePanel" } -- листы: при них подсказок на стекле нет
local GHOST_WINDOW = 10 -- опоздавший "Hold" брошенной (NoReply) кнопки узнаём столько с
local GROUND_UP, GROUND_DOWN = 4, 14 -- луч к земле двора для шевронов: от пояса вора, studs
-- «ГАВ!» собаки (TheftWorldController: TankDisplay.rise в его папке Workspace.TheftWorld —
-- TheftWorldController.Folder(), не поиск по имени: в эмуляторе тестов клиенты делят один
-- Workspace, и находилась папка чужого клиента; Wave 3 ART-09) — над ним «ВЫХОД» не пишется
-- (C1-R2-02); «ГАВ!» всплывает на BarkRise studs — место ему нужно на весь подъём, а не только
-- там, где он сейчас (Stage 4 wave 3: между проверками он вплывал в «ВЫХОД»).
local BARK_NAME = "FxTankPop"
local BARK_RISE = Vector3.new(0, DefenceConfig.World.Dog.BarkRise, 0)
-- Ширина буквы слова мира в долях кегля (Montserrat Heavy Italic); TextScaled не крупнее кегля 100 —
-- в широкой рамке вблизи буквы уже рамки (рамка «ГАВ!» у камеры — 388 px, буквы — 200); у слова с
-- потолком букв (UITextSizeConstraint "Cap": «ГАВ!» — Dog.BarkCap) — не крупнее потолка.
local GLYPH, SCALED_MAX = 0.5, 100

-- Значок подсказки по причине отказа: ожидание (⏳; база, закрытая щитом хозяина, — 🛡️, хозяин
-- настороже — 👀: у всех ожиданий — живые часы до конца), защита, хозяин рядом, остальное — рыба.
local WAIT_REASONS = {
	cooldown = true,
	tagged = true,
	shielded = true,
	wary = true,
	new = true,
	loading = true,
	nobase = true,
	busy = true,
}
local WAIT_ICONS = { shielded = ICONS.Shield, wary = ICONS.Wary } -- (ожидания со своим значком)
local SHIELD_REASONS = { shield = true, join = true, newbie = true, after = true, rest = true }

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
	holder: Frame,
	reason: TextLabel,
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
local firstHintShown = false
local protectWarned = false -- «Начнёшь красть — твоя защита погаснет» уже было за эту защиту
local awaiting = false -- своё удержание начато, ответа сервера ("Hold" / "Denied") ещё нет
local noReplyToken = 0
local holdBeganAt = -math.huge -- (os.clock) своё последнее начало удержания «Украсть»
local heldFor = math.huge -- сколько с держал «Украсть» до того, как отпустил (последнее)
-- Кнопка, на которую сервер не ответил вовремя (NoReply): её опоздавшие "Hold" / "Cancel" —
-- без полосы; ghost — данные опоздавшего "Hold" (если вдруг пришёл и "Carry"). serverAt —
-- серверное время, когда клиент махнул рукой: "Hold" удержания, начатого сервером позже, —
-- новая попытка, не опоздавший ответ (C2-R2-01).
local abandoned: { baseIndex: number, slot: number, at: number, serverAt: number }? = nil
local ghost: { [string]: any }? = nil
local incomingSince = 0 -- (os.clock) TankIncoming стоит с
local reservedPx: number? = nil -- сколько px колонки уведомлений занято (Reserve), nil — нисколько
local resizeTween: Tween? = nil

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

local function baseModel(index: any): Model?
	local folder = Workspace:FindFirstChild("Bases")
	local base = folder and type(index) == "number" and folder:FindFirstChild(`Base_{index}`)
	return if base and base:IsA("Model") then base else nil
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

local function barHeight(): number
	return math.min(SPEC.BarHeight * w.hud.AbsoluteSize.Y, BAR_MAX_HEIGHT)
end

-- Полоса вора на месте: ширина want (nil — полная), высота — BarHeight экрана; в px HUD,
-- записано долями (UDim2.fromScale): по центру экрана, а не влезает — сдвинута в полосу.
-- animate — уже видна: к новой ширине твином за Bar.Resize с (подсказка ↔ кража). wide — шире
-- WidthMax, если want просит (плашка «СОРВАЛОСЬ!»: причина в одну строку на планшете и
-- компьютере, Wave 3 ART-05), но не шире полосы.
local function placeBar(want: number?, animate: boolean?, wide: boolean?)
	local size = w.hud.AbsoluteSize
	if size.X < 2 or size.Y < 2 then
		return
	end
	local height = barHeight()
	local overhang = ICON_SHARE * height
	local left, right = band()
	left += overhang
	local full = math.min(SPEC.Width * size.X, SPEC.WidthMax)
	local cap = if wide and want then math.max(full, want) else full
	local width = math.min(want or full, cap, math.max(right - left, 0))
	local limit = w.bar:FindFirstChildOfClass("UISizeConstraint")
	if limit then
		-- (сборщик держит плашку не шире WidthMax; широкой «СОРВАЛОСЬ!» — её ширина)
		local most = Vector2.new(math.max(SPEC.WidthMax, math.ceil(width)), BAR_MAX_HEIGHT)
		if limit.MaxSize ~= most then
			limit.MaxSize = most
		end
	end
	local center = math.clamp(size.X / 2, left + width / 2, math.max(left + width / 2, right - width / 2))
	local top = math.min(BAR.Top * size.Y, size.Y - BAR.Gap - height)
	local position = UDim2.fromScale(center / size.X, top / size.Y)
	local scale = UDim2.fromScale(width / size.X, height / size.Y)
	local running = resizeTween
	resizeTween = nil
	if running then
		running:Cancel()
	end
	w.bar.AnchorPoint = Vector2.new(0.5, 0)
	if animate and BAR.Resize > 0 and w.bar.Visible and (w.bar.Size ~= scale or w.bar.Position ~= position) then
		resizeTween = UiFx.tween(w.bar, BAR.Resize, { Position = position, Size = scale })
	else
		w.bar.Position = position
		w.bar.Size = scale
	end
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
	local height = barHeight()
	local left, right = band()
	local room = math.min(SPEC.Width * size.X, SPEC.WidthMax, right - left - ICON_SHARE * height)
	local px = UiFx.textSize("Body")
	return FishingLayout.hintWidth(text, px, height, room, UiFx.textWidth(text, px), function(piece: string): number
		return UiFx.textWidth(piece, px)
	end)
end

-- Ширина плашки «СОРВАЛОСЬ!»: заголовок и причина в одну строку (их доля плашки — ширина Title;
-- причина — с запасом FAIL_SLACK на оценку ширины курсива по буквам: на планшете и компьютере
-- «…вернулась домой» иначе переносилось на ободок, Wave 3 ART-05).
local function failWidth(reason: string): number
	local share = math.max(w.title.Size.X.Scale, 0.1)
	local title = UiFx.textWidth(BANNER.Fail, UiFx.textSize("Title"))
	local line = UiFx.textWidth(reason, UiFx.textSize("Body")) * FAIL_SLACK
	return math.max(title, line) / share + FAIL_PAD
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

-- Колонка уведомлений занята целиком, пока кража идёт или ждём ответа на своё удержание.
local function syncToasts(force: boolean?)
	local column = w.hud:FindFirstChild("Toasts")
	local want = awaiting or mode == "hold" or mode == "carry"
	local px: number? = nil
	if want and column and column:IsA("GuiObject") then
		px = math.max(column.AbsoluteSize.Y, 1)
	end
	if px ~= reservedPx or force then
		reservedPx = px
		NotifyController.Reserve(RESERVE_KEY, px)
	end
end

-- Новый вид полосы: старые тикеры и твины — прочь.
local function newMode(next: Mode): number
	modeTrove:Clean()
	generation += 1
	mode = next
	syncToasts()
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

-- Что видно на плашке: подсказка (Line), полоса кражи (Title, Bar с Sub и Time) или срыв
-- (Title и Reason).
local function layoutFor(kind: "hint" | "bar" | "fail")
	local hint, bar = kind == "hint", kind == "bar"
	w.line.Visible = hint
	w.title.Visible = not hint
	local shadow = w.bar:FindFirstChild("TitleShadow")
	if shadow and shadow:IsA("GuiObject") then
		shadow.Visible = not hint
	end
	w.sub.Visible = bar
	w.time.Visible = bar
	w.holder.Visible = bar
	w.reason.Visible = kind == "fail"
	if not bar then
		popAway(w.dog, nil)
	end
end

-- Тикер «1,8 с» / «21 с» до серверного конца endT — цепочка task.delay, пока вид тот же. warn —
-- за сколько с до конца ободок плашки вспыхивает; punchAll — «1,8 с» подпрыгивает на каждой
-- целой секунде (иначе только в последние warn с).
local function tickTime(token: number, endT: number, every: number, whole: boolean, warn: number, punchAll: boolean)
	local lastWhole: number? = nil
	local warned = false
	local function step()
		if token ~= generation then
			return
		end
		local left = math.max(0, endT - serverNow())
		local s = if whole then string.format("%d", math.ceil(left - 1e-6)) else StealRules.FormatSeconds(left)
		w.time.Text = TextUtil.fill(BANNER.Time, { s = s })
		local second = math.ceil(left - 1e-6)
		if lastWhole and second < lastWhole and left > 0 and (punchAll or left <= warn) then
			UiFx.punch(w.time, { from = 0.8, peak = 1.3 })
		end
		lastWhole = second
		if not warned and left <= warn and left > 0 then
			warned = true
			UiFx.rimFlash(w.plate)
		end
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
		return WAIT_ICONS[reason] or ICONS.Wait
	elseif reason and SHIELD_REASONS[reason] then
		return ICONS.Shield
	elseif reason == "owner" then
		return ICONS.Owner
	elseif reason == "stealing" then
		return ICONS.Hold
	end
	return ICONS.Fish
end

-- Открыт лист (садок, «ЗАЩИТА»): подсказка на стекле над ним не рисуется.
local function sheetOpen(): boolean
	for _, name in SHEETS do
		local sheet = w.hud:FindFirstChild(name)
		if sheet and sheet:IsA("GuiObject") and sheet.Visible then
			return true
		end
	end
	return false
end

local function hideHint()
	if mode == "hint" then
		newMode("none")
		hintKey = nil
		hideBar()
	end
end

-- Подсказка на стекле; forSeconds — сколько секунд держать (nil — пока её не сменит цепочка двора).
local function showHint(text: string, emoji: string, forSeconds: number?, key: string?)
	if mode ~= "none" and mode ~= "hint" then
		return
	end
	if sheetOpen() then
		hideHint()
		return
	end
	local same = mode == "hint" and hintKey == key and key ~= nil
	local wasShown = isShown(w.bar)
	if mode ~= "hint" then
		newMode("hint")
	end
	hintKey = key
	hintUntil = if forSeconds then os.clock() + forSeconds else 0
	UiFx.setCandy(w.plate, "Glass")
	layoutFor("hint")
	setIcon(emoji)
	w.line.Text = text
	placeBar(hintWidth(text), wasShown)
	if not wasShown then
		showBar()
	elseif not same then
		UiFx.punch(w.line, { from = 0.85, peak = 1.06 })
	end
end

-- Первая подсказка — по последнему вводу (тач, геймпад, клавиатура; ничего ещё не нажимал — по
-- устройству).
local function firstText(): string
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return TEXTS.Hint.Touch
	elseif string.find(last.Name, "Gamepad", 1, true) then
		return TEXTS.Hint.Gamepad
	elseif last == Enum.UserInputType.Keyboard or string.find(last.Name, "Mouse", 1, true) then
		return TEXTS.Hint.Keyboard
	elseif UserInputService.TouchEnabled then
		return TEXTS.Hint.Touch
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return TEXTS.Hint.Gamepad
	end
	return TEXTS.Hint.Keyboard
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
	local base = baseModel(player:GetAttribute("BaseIndex"))
	local untilT = base and base:GetAttribute("ProtectUntil")
	return finite(untilT) and (untilT :: number) > serverNow()
end

-- Шаг цепочки «вор во дворе»: что написать на стекле (или убрать подсказку).
local function plotStep(root: BasePart)
	local base = foreignPlot(root)
	local protected = ownProtected()
	if not protected then
		protectWarned = false -- (защита кончилась: следующая снова предупредит)
	end
	if mode ~= "none" and mode ~= "hint" then
		return -- (кража, срыв, «ДОБЫЧА!» — у них своя полоса)
	end
	if player:GetAttribute("Stealing") ~= nil then
		return -- (своя кража уже идёт — её полоса; атрибут бывает раньше "Hold": не причина двора)
	end
	if sheetOpen() then
		hideHint() -- (лист открыт; закроется — подсказка вернётся на следующем шаге)
		return
	end
	if mode == "hint" and hintUntil > os.clock() and (base ~= nil or hintKey == nil) then
		return -- (отказ, «подожди», первая подсказка — держатся своё время; подсказка двора — пока он во дворе)
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
	-- По очереди, каждая — HintTime: сначала про свою защиту (раз за защиту — до первой кражи под
	-- ней: случайный тап её не гасит, UX-01), потом как красть (раз за игру).
	if protected and not protectWarned then
		protectWarned = true
		showHint(TEXTS.Hint.Protected, ICONS.Shield, BAR.HintTime, "protected")
		return
	elseif not firstHintShown then
		firstHintShown = true
		showHint(firstText(), ICONS.Hint, BAR.HintTime, "first")
		return
	end
	if mode == "hint" and hintUntil <= os.clock() then
		hideHint()
	end
end

local function startPlotChain(character: Model)
	characterTrove:Clean()
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
	awaiting = false
	celebrationTrove:Clean()
	popAway(w.slam, nil)
	carryTrove:Clean()
	local wasShown = isShown(w.bar)
	local token = newMode("hold")
	hintKey = nil
	UiFx.setCandy(w.plate, "Night")
	UiFx.setCandy(w.fill, "Berry")
	layoutFor("bar")
	setIcon(ICONS.Hold)
	local t = theft :: Theft
	w.title.Text = TextUtil.fill(BANNER.Hold, { short = TextUtil.upper(t.short) })
	w.sub.Text = BANNER.HoldSub
	placeBar(nil, wasShown)
	showBar()
	UiFx.punch(w.title, { from = 0.8, peak = 1.08 })
	runFill(endT, need, true)
	tickTime(token, endT, BAR.HoldTick, false, BAR.HoldWarn, true)
end

-- Земля двора под точкой: луч по Grounds и Arcades базы (не по скамейкам и витринам), за оградой —
-- по миру; ничего — уровень ног вора.
local function groundParams(base: Model): RaycastParams?
	local list = {}
	for _, name in { "Grounds", "Arcades" } do
		local found = base:FindFirstChild(name)
		if found then
			table.insert(list, found)
		end
	end
	if #list == 0 then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = list
	return params
end

-- Рамка слова мира на экране (px, как AbsolutePosition) или nil: выключено, без Adornee-детали,
-- за камерой. Size: Scale — studs, Offset — px (как у TankWorldController). text — по ширине букв
-- этой надписи (TextScaled), а не всей рамки.
local function wordBox(
	gui: BillboardGui,
	camera: Camera,
	text: string?,
	offset: Vector3? -- вместо gui.StudsOffset (куда слово ещё всплывёт)
): { x0: number, y0: number, x1: number, y1: number }?
	local adornee = gui.Adornee
	if not gui.Enabled or not (adornee and adornee:IsA("BasePart")) then
		return nil
	end
	local at = adornee.Position
		+ gui.StudsOffsetWorldSpace
		+ camera.CFrame:VectorToWorldSpace(offset or gui.StudsOffset)
	local p = camera:WorldToScreenPoint(at)
	if p.Z <= 0.05 or (at - camera.CFrame.Position).Magnitude > gui.MaxDistance then
		return nil
	end
	local perStud = camera.ViewportSize.Y / (2 * p.Z * math.tan(math.rad(camera.FieldOfView) / 2))
	local size = gui.Size
	local w = size.X.Scale * perStud + size.X.Offset
	local h = size.Y.Scale * perStud + size.Y.Offset
	if text then
		local cap = gui:FindFirstChild("Cap", true)
		local most = if cap and cap:IsA("UITextSizeConstraint")
			then math.min(cap.MaxTextSize, SCALED_MAX)
			else SCALED_MAX
		h = math.min(h, most)
		w = math.min(w, (utf8.len(text) or #text) * GLYPH * h)
	end
	return { x0 = p.X - w / 2, y0 = p.Y - h / 2, x1 = p.X + w / 2, y1 = p.Y + h / 2 }
end

local function guidePart(name: string, size: Vector3, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = size
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Красная дорожка на земле (папка Workspace.TheftGuide): шевроны от вора к ближайшему выходу
-- ползут к нему, у выхода — зелёное кольцо и «ВЫХОД»; переставляется раз в BeamEvery с.
local function startGuide()
	local t = theft
	local base = t and baseModel(t.baseIndex)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (base and root and root:IsA("BasePart")) then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "TheftGuide"
	carryTrove:Add(folder)
	-- Шевроны: две палочки «>» остриём к выходу (Width поперёк, Length вдоль).
	local arm = math.sqrt((GUIDE.Width / 2) ^ 2 + GUIDE.Length ^ 2)
	local angle = math.atan2(GUIDE.Width / 2, GUIDE.Length)
	local red = Palette.Berry.Bottom
	local arrows: { { Part } } = {}
	for index = 1, GUIDE.Arrows do
		local model = Instance.new("Model")
		model.Name = `Arrow_{index}`
		local size = Vector3.new(GUIDE.Bar, 0.2, arm + GUIDE.Bar)
		arrows[index] = { guidePart("Left", size, red, model), guidePart("Right", size, red, model) }
		model.Parent = folder
	end
	-- У выхода: зелёное кольцо (диск — Cylinder осью вверх) дышит, над ним «ВЫХОД».
	local ring = guidePart("Ring", Vector3.new(0.2, GUIDE.Ring, GUIDE.Ring), Palette.Leaf.Top, folder)
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.3
	local pulse = TweenService:Create(
		ring,
		TweenInfo.new(GUIDE.RingPeriod / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Size = Vector3.new(0.2, GUIDE.Ring * GUIDE.RingPulse, GUIDE.Ring * GUIDE.RingPulse), Transparency = 0.55 }
	)
	pulse:Play()
	carryTrove:Add(function()
		pulse:Cancel()
	end)
	local spec = GUIDE.Label
	local label, plate =
		TankDisplay.billboard(folder, "ExitLabel", UDim2.fromOffset(spec.PixelsX, spec.PixelsY), GUIDE.LabelRange)
	label.Adornee = ring
	label.AlwaysOnTop = true
	label.StudsOffsetWorldSpace = Vector3.new(0, spec.Lift, 0)
	TankDisplay.word(plate, "Word", TEXTS.Exit, { 0, 0, 1, 1 }, Palette.Leaf, 3)
	folder.Parent = Workspace
	TankWorldController.TrackWord(label)
	-- «ВЫХОД» и «ГАВ!» — оба поверх всего: где они сошлись на экране (у «ГАВ!» — на весь его
	-- подъём), табличка ждёт, пока «ГАВ!» не уйдёт. Проверка — на каждом шаге дорожки и, пока
	-- «ГАВ!» живёт (≈ 1 с), раз в Guide.BarkEvery с: он едет с бегущей собакой и растёт, подбегая
	-- к камере (Stage 4 wave 3: между шагами дорожки он вплывал в «ВЫХОД»). Enabled — наш,
	-- прозрачность — у TrackWord.
	local clearPad = spec.Clear
	local function clearOfBark()
		local camera = Workspace.CurrentCamera
		local barks = TheftWorldController.Folder()
		if label.Parent == nil or not camera then
			return
		end
		label.Enabled = true
		local mine = if barks then wordBox(label, camera) else nil
		if not mine then
			return
		end
		for _, item in (barks :: Instance):GetChildren() do
			if item.Name == BARK_NAME and item:IsA("BillboardGui") then
				local word = item:FindFirstChildWhichIsA("TextLabel", true)
				local text = if word then word.Text else nil
				local other = wordBox(item, camera, text)
				local risen = wordBox(item, camera, text, BARK_RISE) -- (весь подъём «ГАВ!»)
				if other and risen then
					other = {
						x0 = math.min(other.x0, risen.x0),
						y0 = math.min(other.y0, risen.y0),
						x1 = math.max(other.x1, risen.x1),
						y1 = math.max(other.y1, risen.y1),
					}
				end
				if
					other
					and mine.x0 < other.x1 + clearPad
					and mine.x1 > other.x0 - clearPad
					and mine.y0 < other.y1 + clearPad
					and mine.y1 > other.y0 - clearPad
				then
					label.Enabled = false
					return
				end
			end
		end
	end
	local barks = TheftWorldController.Folder()
	if barks then
		local watching, stopped = false, false
		carryTrove:Add(function()
			stopped = true
		end)
		-- Цепочка task.delay, только пока в папке есть «ГАВ!» (покадровой работы нет).
		local function watchBarks()
			if stopped or label.Parent == nil then
				watching = false
				return
			end
			clearOfBark()
			if (barks :: Instance):FindFirstChild(BARK_NAME) then
				task.delay(GUIDE.BarkEvery, watchBarks)
			else
				watching = false
			end
		end
		local function changed(item: Instance)
			if item.Name ~= BARK_NAME then
				return
			end
			-- (Adornee и сдвиг «ГАВ!» пишутся сразу после появления — проверка на defer)
			if watching then
				task.defer(clearOfBark)
			else
				watching = true
				task.defer(watchBarks)
			end
		end
		carryTrove:Add(barks.ChildAdded:Connect(changed))
		carryTrove:Add(barks.ChildRemoved:Connect(changed))
		-- «ГАВ!» уже висит (собака гавкнула при начале удержания, до выноса): цепочка сразу
		if barks:FindFirstChild(BARK_NAME) then
			watching = true
			task.defer(watchBarks)
		end
	end
	local params = groundParams(base)
	-- (за оградой двора — дорожки хаба: любой мир под точкой, кроме персонажа и самой дорожки)
	local world = RaycastParams.new()
	world.FilterType = Enum.RaycastFilterType.Exclude
	world.FilterDescendantsInstances = { character :: Model, folder }
	local alive = true
	carryTrove:Add(function()
		alive = false
	end)
	local phase = 0
	local function aim()
		if not alive or root.Parent == nil then
			return
		end
		local hip = if humanoid then humanoid.HipHeight else 2
		local feet = root.Position.Y - hip - root.Size.Y / 2
		local function groundAt(x: number, z: number): number
			local from = Vector3.new(x, root.Position.Y + GROUND_UP, z)
			local hit = if params then Workspace:Raycast(from, Vector3.new(0, -GROUND_DOWN, 0), params) else nil
			hit = hit or Workspace:Raycast(from, Vector3.new(0, -GROUND_DOWN, 0), world)
			return if hit then hit.Position.Y else feet
		end
		local pivot = base:GetPivot()
		local exitLocal = StealRules.NearestExit(StealRules.LocalOf(pivot, root.Position))
		local exit = pivot * Vector3.new(exitLocal.X, 0, exitLocal.Z)
		local here = Vector3.new(root.Position.X, 0, root.Position.Z)
		local ahead = Vector3.new(exit.X, 0, exit.Z) - here
		local distance = ahead.Magnitude
		local dir = if distance > 0.01 then ahead.Unit else root.CFrame.LookVector
		ring.CFrame = CFrame.new(exit.X, groundAt(exit.X, exit.Z) + GUIDE.Lift, exit.Z)
			* CFrame.Angles(0, 0, math.pi / 2)
		-- (бегущие огни: каждый шаг цепочки — на Step / Crawl ближе к выходу)
		phase = (phase + 1) % GUIDE.Crawl
		local shift = phase / GUIDE.Crawl * GUIDE.Step
		for index, pair in arrows do
			local along = GUIDE.Start + (index - 1) * GUIDE.Step + shift
			local hidden = along > distance - GUIDE.Ring / 2
			local spot = here + dir * along
			local at = Vector3.new(spot.X, groundAt(spot.X, spot.Z) + GUIDE.Lift, spot.Z)
			local frame = CFrame.lookAt(at, at + dir)
			pair[1].CFrame = frame * CFrame.new(-GUIDE.Width / 4, 0, 0) * CFrame.Angles(0, -angle, 0)
			pair[2].CFrame = frame * CFrame.new(GUIDE.Width / 4, 0, 0) * CFrame.Angles(0, angle, 0)
			for _, part in pair do
				part.Transparency = if hidden then 1 else 0
			end
		end
		clearOfBark()
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
			UiFx.wiggle(w.dog, 8, 2, 0.4)
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
	layoutFor("bar")
	setIcon(ICONS.Carry)
	w.title.Text = BANNER.Carry
	w.sub.Text = BANNER.CarrySub
	placeBar(nil)
	showBar()
	UiFx.rimFlash(w.plate)
	UiFx.punch(w.title, { from = 0.7, peak = 1.12 })
	UiFx.punch(w.holder, { from = 0.85, peak = 1.1 })
	runFill(endT, StealConfig.Carry.Timeout, false)
	tickTime(token, endT, BAR.CarryTick, true, BAR.CarryWarn, false)
	incomingSince = os.clock()
	setHud("TankIncoming", t.rarity)
	carryTrove:Clean()
	startGuide()
	watchDog()
	-- «ДОМОЙ» под замком нажали (HudController: атрибут HUD HomeLockedTap) — строка полосы говорит
	-- почему, на Bar.LockedTime с, и снова «Не попадись хозяину» (Wave 3 UX-07: только качание и 🔒
	-- ничего не объясняли)
	local said = 0
	carryTrove:Add(w.hud:GetAttributeChangedSignal("HomeLockedTap"):Connect(function()
		if mode ~= "carry" or generation ~= token then
			return
		end
		said += 1
		local mine = said
		w.sub.Text = BANNER.HomeLocked
		UiFx.punch(w.sub, { from = 0.8, peak = 1.15 })
		UiFx.flashText(w.sub, Palette.Sun.Top, 0.4)
		task.delay(BAR.LockedTime, function()
			if mine == said and mode == "carry" and generation == token then
				w.sub.Text = BANNER.CarrySub
			end
		end)
	end))
end

-- Кража кончилась (срыв, «ДОБЫЧА!», молча): вынос и прилёт — прочь, кнопка больше не своя.
local function dropTheft()
	carryTrove:Clean()
	theft = nil
	awaiting = false
end

-- "Cancel" с BaseUntil: база хозяина закрыта для вора до BaseUntil (серверное время) по причине
-- BaseReason ("tagged" | "shielded" | "wary") — её кнопки прячутся, двор говорит почему, с часами
-- (S-02, S-05, S-06); сервер без BaseUntil и «tag» — на TagCooldown (пара вор–хозяин).
local function closeBase(baseIndex: any, data: { [string]: any })
	local base = baseModel(baseIndex)
	local owner = base and base:GetAttribute("OwnerUserId")
	if type(owner) ~= "number" then
		return
	end
	if finite(data.BaseUntil) then
		TheftPrompts.SetTagged(
			owner,
			data.BaseUntil,
			if type(data.BaseReason) == "string" then data.BaseReason else nil
		)
	elseif data.Reason == "tag" then
		TheftPrompts.SetTagged(owner, serverNow() + LIMITS.TagCooldown, "tagged")
	end
end

local function enterFail(data: { [string]: any })
	local t = theft
	if data.Phase == "hold" then
		endHold(heldPrompt()) -- (сервер кнопку не выключает: так щит или касание гасят кольцо)
	end
	closeBase(if t then t.baseIndex else data.BaseIndex, data)
	releaseIncoming()
	dropTheft()
	-- Короткий тап по «Украсть» — не срыв: подсказка, как держать (без тряски и звука).
	if data.Reason == "released" and data.Phase == "hold" and heldFor < LIMITS.QuietSavedUnder then
		newMode("none")
		showHint(TEXTS.Hint.HoldLonger, ICONS.Hint, SPEC.DeniedHint, nil)
		return
	end
	local reason = if type(data.Text) == "string" and data.Text ~= "" then data.Text else TEXTS.Cancel.busy
	local token = newMode("fail")
	UiFx.setCandy(w.plate, "Berry")
	layoutFor("fail")
	setIcon(ICONS.Fail)
	w.title.Text = BANNER.Fail
	w.reason.Text = reason
	placeBar(failWidth(reason), nil, true)
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
	dropTheft()
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

-- Ответ про кнопку, на которую NoReply уже махнул рукой (опоздал): data — её BaseIndex / Slot,
-- и сервер начал это удержание (End − Need) не позже, чем клиент сдался; начатое позже — новое
-- удержание той же кнопки (тот же ребёнок снова держит «Украсть»), его полоса — как обычно.
local function isAbandoned(data: { [string]: any }): boolean
	local gone = abandoned
	if gone == nil or os.clock() - gone.at >= GHOST_WINDOW then
		return false
	end
	if data.BaseIndex ~= gone.baseIndex or data.Slot ~= gone.slot then
		return false
	end
	if finite(data.End) and finite(data.Need) then
		return (data.End :: number) - (data.Need :: number) <= gone.serverAt
	end
	return true
end

local function onDenied(data: { [string]: any })
	awaiting = false
	noReplyToken += 1
	abandoned = nil
	syncToasts()
	endHold(TheftPrompts.PromptAt(data.BaseIndex, data.Slot))
	-- Отказ со сроком (Until): кнопки этой причины спрятаны до него (и тихий повтор — тоже)
	if finite(data.Until) and type(data.Reason) == "string" then
		TheftPrompts.SetDenied(data.BaseIndex, data.Slot, data.Reason, data.Until)
	end
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
		noReplyToken += 1
		if isAbandoned(d) then
			-- (опоздал: кольцо уже погашено, «Подожди секунду» на стекле — полосы нет)
			awaiting = false
			ghost = d
			syncToasts()
			return
		end
		abandoned, ghost = nil, nil
		enterHold(d)
	elseif kind == "Carry" then
		local late = ghost
		if late and not theft then
			ghost, abandoned = nil, nil
			enterHold(late) -- (сервер всё-таки засчитал удержание: вынос — как обычно)
		end
		enterCarry(d)
	elseif kind == "Cancel" then
		local late = ghost
		if late and not theft then
			ghost, abandoned = nil, nil
			closeBase(late.BaseIndex, d) -- (опоздавший ответ тоже закрывает базу)
			showHint(BANNER.NoReply, ICONS.Wait, SPEC.DeniedHint, nil)
			return
		end
		enterFail(d)
	elseif kind == "Done" then
		ghost, abandoned = nil, nil
		enterDone(d)
	elseif kind == "Denied" then
		onDenied(d)
	elseif kind == "Returned" and d.Result == nil and type(d.Text) == "string" then
		NotifyController.Show(d.Text, "warning", { icon = ICONS.Fly })
	end
end

-- Своё начало удержания «Украсть»: эта кнопка не прячется; нет ответа за NoReply с (или за
-- пинг с запасом) — гасим; уведомления ждут.
local function onHoldBegan(prompt: ProximityPrompt)
	if not TheftPrompts.IsSteal(prompt) then
		return
	end
	TheftPrompts.SetHeld(prompt)
	holdBeganAt = os.clock()
	heldFor = math.huge
	awaiting = theft == nil
	syncToasts()
	noReplyToken += 1
	local token = noReplyToken
	local ping = player:GetNetworkPing()
	local patience =
		math.max(StealConfig.Hold.NoReply, (if finite(ping) then ping else 0) + StealConfig.Hold.NoReplySlack)
	task.delay(patience, function()
		if token ~= noReplyToken or not awaiting then
			return
		end
		awaiting = false
		syncToasts()
		local baseIndex, slot = TheftPrompts.SlotOf(prompt)
		if baseIndex and slot then
			abandoned = { baseIndex = baseIndex, slot = slot, at = os.clock(), serverAt = serverNow() }
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
	heldFor = os.clock() - holdBeganAt
	TheftPrompts.SetHeld(nil)
	if awaiting then
		-- (отпустил раньше ответа: «нет ответа» уже не про него; уведомления ждут ответа сервера
		-- не дольше NoReply — "Cancel" или "Denied" придут, а если нет — колонка свободна)
		noReplyToken += 1
		local token = noReplyToken
		task.delay(StealConfig.Hold.NoReply, function()
			if token == noReplyToken and awaiting then
				awaiting = false
				syncToasts()
			end
		end)
	end
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
					dropTheft()
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
		holder = barHolder,
		reason = child(bar, "Reason"),
		line = child(bar, "Line"),
		dog = child(bar, "DogChip"),
		slam = slam,
		slamTitle = child(slam, "Title"),
		slamSub = child(slam, "Sub"),
	}
	bar.Visible = false
	slam.Visible = false
	w.dog.Visible = false

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

	-- Экран поменял размер — полоса и «ДОБЫЧА!» встают на место, колонка уведомлений — занята
	-- вся по-новому.
	hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if w.bar.Visible then
			if mode == "hint" then
				placeBar(hintWidth(w.line.Text))
			elseif mode == "fail" then
				placeBar(failWidth(w.reason.Text), nil, true)
			else
				placeBar(nil)
			end
		end
		if w.slam.Visible then
			placeSlam()
		end
		if reservedPx then
			task.defer(syncToasts, true)
		end
	end)

	-- Цепочка «вор во дворе» живёт с персонажем.
	player.CharacterAdded:Connect(startPlotChain)
	player.CharacterRemoving:Connect(function()
		characterTrove:Clean()
	end)
	if player.Character then
		startPlotChain(player.Character)
	end
end

return TheftController
