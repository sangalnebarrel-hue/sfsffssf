--!strict
--[[
	DefenceController — защита своей базы на экране (Этап 4): кнопка «ЗАЩИТА» справа, фишка щита у
	плашки базы и лист «ЗАЩИТА» с карточками Щит · Собака · Сигнализация · Замок
	(docs/stage4_design.md §6.2, §6.5, §6.6; виджеты — HUD.RightButtons.DefenceButton,
	HUD.Status.BaseBadge.ShieldChip (tools/builder/gui/Hud.luau), HUD.DefencePanel
	(tools/builder/gui/Defence.luau на оболочке gui/Sheet.luau); числа — DefenceConfig, UIConfig,
	тексты — DefenceConfig.Texts). Карточки листа рисует помощник Controllers.DefenceCards (модуль, не
	контроллер), лист открывает и раскладывает помощник Controllers.Sheet (один лист на экране).

	Что делает:
	  • Кнопка «ЗАЩИТА» (Guard 🛡️, третья в колонке над «САДОК»): видна, когда есть база и данные
	    загружены; выскакивает после «САДОК» во вступлении (плашка → кошелёк → «САДОК» → «ЗАЩИТА»
	    через UIConfig.Wallet.IntroGap; масштаб на своём месте — не Position колонки). Нажатие —
	    Toggle() листа; занято (поклёвка, мини-игра, карточка улова) — кнопка качается «нет».
	  • «ЩИТ!» (тревога): атрибут HUD AlertPhase ("hold" | "carry", его ставит AlertController),
	    щит готов (атрибут игрока ShieldReadyAt ≤ сейчас) и игрок не крадёт сам (Stealing) — подпись
	    «ЩИТ!», лицо Berry, красные кольца (UiFx.glowRing loop) и «!»; нажатие — ShieldActivate
	    сразу, без листа: работает и во время мини-игры (её ввод — только кнопка действия).
	  • Перезарядка (ShieldReadyAt > сейчас): тёмная вуаль Cooldown стекает (один линейный твин
	    градиента Drain на оставшееся), CooldownText «2:59» — цепочка task.delay раз в секунду,
	    только пока лист закрыт; готов — вуаль уходит, «ГОТОВ!» на подписи Theft.ReadyPop с, кольцо,
	    уведомление «Щит снова готов!».
	  • «!» один раз за игру — когда впервые хватает денег на защиту, которой нет (DC-13); гаснет при
	    открытии листа. Bob(seconds) — кнопка подпрыгивает (гость во дворе — AlertController; конец
	    защиты входа — здесь).
	  • Фишка «🛡️ 0:42» (ShieldChip у правого края плашки базы): пока ProtectUntil своей базы >
	    сейчас — любая защита (щит — сплошная Guard, остальные — стекло); цепочка раз в секунду;
	    последние Shield.WarnLast с — вспышка Sun и подпрыгивание каждую секунду; конец — popOut
	    («Щит погас» присылает сервер). Ждёт баннер базы (виден BaseBanner — нет), выскакивает после
	    плашки.
	  • Уведомления: первая защита входа за игру — «Защита новичка 5:00 🛡️ — лови спокойно!» /
	    «Твой садок под защитой 1:30»; за Shield.EndingWarn с до конца защиты входа / новичка —
	    «Скоро воры! Увидишь 🚨 — жми 🛡️ ЩИТ!» и кнопка подпрыгивает (здесь ребёнок узнаёт про
	    щит); щит включён — «Щит включён на 1:00» (во время тревоги — через MERGE_WAIT с: щит кончил
	    кражу — AlertController забирает его (TakeShieldToast) в одно «Щит спас рыбу! 🛡️ 1:00»);
	    отказ сервера — его текст (Sun) и кнопка, с которой просили, качается. Уведомления защиты
	    при открытом листе ждут его ухода (NotifyController Look.afterSheet: легли бы на шапку с
	    кошельком; на «ЗАЩИТА» то же видно на карточке щита), таймер в них — на миг показа и дальше
	    секунда в секунду с фишкой щита, пока уведомление на экране (Look.clock, last-mile F-12).
	  • Лист «ЗАЩИТА»: DefenceCards — карточки, покупка в два нажатия (DefenceBuy), ответы
	    DefenceEvent "Bought" (MoneyController.Spend: 💵 из кошелька в карточку, «−$6 000»; штамп
	    «КУПЛЕНО», конфетти, уведомление) / "Denied" (качается, уведомление) / "Shield".
	Сервер решает всё: клиент только просит (ShieldActivate, DefenceBuy) и показывает атрибуты.
	Покой — ни одного покадрового соединения (цепочки task.delay — только пока идёт защита или
	перезарядка, лист открыт); соединения листа — в его Trove.

	API:
	  DefenceController.Toggle() -> boolean      -- открыть / закрыть лист «ЗАЩИТА»
	  DefenceController.IsOpen() -> boolean
	  DefenceController.ActivateShield(from: GuiObject?) -> boolean  -- попросить щит (плашка тревоги,
	                                             -- кнопка «ЩИТ!», карточка); from качается при отказе;
	                                             -- пока сервер не ответил — false (одна просьба)
	  DefenceController.ShieldReady() -> boolean -- щит готов (ShieldReadyAt ≤ сейчас)
	  DefenceController.Bob(seconds: number)     -- кнопка «ЗАЩИТА» подпрыгивает столько с
	  DefenceController.AlertRest(rest)          -- кольца «ЩИТ!» отдыхают (телефон: у рыбалки свой
	                                             -- светящийся край — заливка; «ЩИТ!» и «!» остаются)
	  DefenceController.TakeShieldToast() -> number -- щит спас рыбу: «Щит включён» не показывать
	                                             -- (уже показан — не отменить); сколько с щита
	  DefenceController.Stats() -> { ... }       -- тесты: chains, open, alert, cooldown
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local DefenceConfig = require(Config:WaitForChild("DefenceConfig"))
local UIConfig = require(Config:WaitForChild("UIConfig"))
local Net = require(Shared:WaitForChild("Net"))
local StealRules = require(Shared:WaitForChild("StealRules"))
local TextUtil = require(Shared:WaitForChild("TextUtil"))
local Trove = require(Shared:WaitForChild("Util"):WaitForChild("Trove"))
local UiFx = require(Shared:WaitForChild("UiFx"))
local Controllers = script.Parent
local NotifyController = require(Controllers:WaitForChild("NotifyController"))
local DefenceCards = require(Controllers:WaitForChild("DefenceCards"))

local player = Players.LocalPlayer
local TEXTS = DefenceConfig.Texts
local SHIELD = DefenceConfig.Shield
local THEFT = UIConfig.Theft
local Palette = UIConfig.Palette
local CYCLE = SHIELD.Duration + SHIELD.Cooldown -- от включения до готовности, с
local ALERT_RING = { Scale = 1.3, Thickness = 5, Time = 0.6, Every = 0.9 } -- кольца «ЩИТ!»
local BOB_EVERY = { 0.45, 0.6 } -- кнопка «ЗАЩИТА» подпрыгивает раз в столько с (Bob)
local CHIP_BUMP = 1.25 -- фишка «🛡️ 0:09» в последние секунды
local SHIELD_WAIT = 3 -- нет ответа на ShieldActivate столько с — «⏳» уходит
-- Щит включён во время тревоги: «Щит включён» ждёт столько с — кража кончится щитом, и
-- AlertController покажет одно «Щит спас рыбу! 🛡️ 1:00»; «Saved» пришёл раньше — столько с
-- «Щит включён» не нужен (TakeShieldToast)
local MERGE_WAIT = 1
local INTRO_STEPS = 3 -- «ЗАЩИТА» — через столько Wallet.IntroGap после вступления (после «САДОК»)
local JOIN_KINDS: { [string]: boolean } = { join = true, newbie = true }
-- Уведомления защиты при открытом листе ждут его ухода (легли бы на шапку с кошельком; на
-- «ЗАЩИТА» то же видно на карточке щита) — NotifyController Look.afterSheet
local AFTER_SHEET: NotifyController.Look = { afterSheet = true }

local DefenceController = {}

-- Всё состояние — в одной таблице (свободные регистры верхнего уровня).
local S = {
	hud = nil :: ScreenGui?,
	button = nil :: GuiButton?,
	caption = nil :: TextLabel?,
	icon = nil :: GuiObject?,
	badge = nil :: GuiObject?,
	veil = nil :: GuiObject?,
	drain = nil :: UIGradient?,
	veilText = nil :: TextLabel?,
	chip = nil :: GuiObject?,
	chipLabel = nil :: TextLabel?,
	base = nil :: Model?,
	baseTrove = Trove.new(), -- соединения своей базы (ProtectUntil, ProtectKind)
	alertTrove = Trove.new(), -- вид «ЩИТ!»
	ringTrove = Trove.new(), -- его красные кольца
	ringRest = false, -- кольца отдыхают (AlertRest)
	bobStop = nil :: (() -> ())?,
	bobUntil = 0,
	alert = false, -- кнопка сейчас «ЩИТ!»
	shownOnce = false,
	cooldownGen = 0,
	cooldownOn = false,
	readyAtShown = 0, -- ShieldReadyAt, под которую стоит вуаль
	chipGen = 0,
	chipOn = false,
	chipKind = nil :: string?,
	warned = nil :: number?, -- ProtectUntil, о конце которой уже предупредили
	greeted = false, -- уведомление о защите входа уже было
	affordShown = false, -- «!» «хватает на защиту» уже был
	affordBadge = false, -- «!» сейчас горит из-за него
	shieldFrom = nil :: GuiObject?, -- кто просил щит (качается при отказе)
	shieldWait = nil :: thread?,
	shieldToast = nil :: thread?, -- отложенное «Щит включён» (тревога)
	shieldTaken = -math.huge, -- когда AlertController забрал «Щит включён» в «Щит спас рыбу!»
	cards = nil :: any, -- DefenceCards
}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function numberAttr(inst: Instance?, name: string): number?
	local value = if inst then inst:GetAttribute(name) else nil
	return if typeof(value) == "number" and value == value then value else nil
end

local function cancel(thread: thread?)
	if thread and coroutine.status(thread) == "suspended" then
		task.cancel(thread)
	end
end

local function readyAt(): number
	return numberAttr(player, "ShieldReadyAt") or 0
end

function DefenceController.ShieldReady(): boolean
	return readyAt() <= now()
end

-- Своя база (Workspace.Bases.Base_N по BaseIndex) или nil.
local function ownBase(): Model?
	local index = numberAttr(player, "BaseIndex")
	local bases = Workspace:FindFirstChild("Bases")
	if not index or index <= 0 or not bases then
		return nil
	end
	local base = bases:FindFirstChild(`Base_{index}`)
	return if base and base:IsA("Model") then base else nil
end

-- Защита своей базы сейчас: (вид, конец) или nil.
local function protection(): (string?, number?)
	local base = S.base
	local untilAt = numberAttr(base, "ProtectUntil")
	local kind = if base then base:GetAttribute("ProtectKind") else nil
	if untilAt and untilAt > now() and typeof(kind) == "string" then
		return kind, untilAt
	end
	return nil, nil
end

local function wanted(): boolean
	local hud = S.hud
	local index = numberAttr(player, "BaseIndex")
	local mode = player:GetAttribute("DataMode")
	return hud ~= nil
		and index ~= nil
		and index > 0
		and (mode == "Ready" or mode == "Memory")
		and typeof(hud:GetAttribute("IntroAt")) == "number"
end

--------------------------------------------------------------------------------
-- Щит: просьба и ответ
--------------------------------------------------------------------------------

function DefenceController.ActivateShield(from: GuiObject?): boolean
	if not S.hud or S.shieldWait then
		-- (уже попросили — ждём ответа: одна просьба на все кнопки щита, не дольше SHIELD_WAIT)
		return false
	end
	S.shieldFrom = from
	cancel(S.shieldWait)
	S.shieldWait = task.delay(SHIELD_WAIT, function()
		S.shieldWait = nil
		S.shieldFrom = nil
		if S.cards then
			S.cards:ShieldAnswered(false)
		end
	end)
	Net.Event("ShieldActivate"):FireServer()
	if from then
		UiFx.punch(from, { from = 0.85, peak = 1.1 })
	end
	UiFx.sound("click", 0.4, 1.2)
	return true
end

--------------------------------------------------------------------------------
-- Кнопка «ЗАЩИТА»
--------------------------------------------------------------------------------

local function setCaption(text: string, punch: boolean)
	local caption = S.caption
	if caption and caption.Text ~= text then
		UiFx.setText(caption, text)
		if punch then
			UiFx.punch(caption, { from = 0.6, peak = 1.15 })
		end
	end
end

local function restCaption(): string
	return if S.alert then TEXTS.ButtonAlert else TEXTS.Button
end

-- «!»: тревога («ЩИТ!») или «хватает на защиту» (один раз за игру, до открытия листа).
local function syncBadge()
	local badge = S.badge
	if not badge then
		return
	end
	local want = S.alert or S.affordBadge
	if want and not badge.Visible then
		UiFx.badgeBob(badge)
	elseif not want and badge.Visible then
		UiFx.badgeHide(badge)
	end
end

local function alertWanted(): boolean
	local hud = S.hud
	local phase = if hud then hud:GetAttribute("AlertPhase") else nil
	return (phase == "hold" or phase == "carry")
		and DefenceController.ShieldReady()
		and player:GetAttribute("Stealing") == nil
end

-- Красные кольца «ЩИТ!»: пока кнопка «ЩИТ!» и не отдыхают (AlertRest).
local function syncRing()
	S.ringTrove:Clean()
	local button = S.button
	if button and S.alert and not S.ringRest then
		S.ringTrove:Add(UiFx.glowRing(button, {
			color = Palette.Berry.Top,
			scale = ALERT_RING.Scale,
			thickness = ALERT_RING.Thickness,
			time = ALERT_RING.Time,
			interval = ALERT_RING.Every,
			loop = true,
		}))
	end
end

function DefenceController.AlertRest(rest: boolean)
	if (rest == true) ~= S.ringRest then
		S.ringRest = rest == true
		syncRing()
	end
end

-- «ЗАЩИТА» ↔ «ЩИТ!» (тревога, щит готов, сам не крадёшь).
local function syncAlert()
	local button = S.button
	if not button then
		return
	end
	local want = alertWanted()
	if want == S.alert then
		return
	end
	S.alert = want
	S.alertTrove:Clean()
	if not want then
		S.ringRest = false
	end
	syncRing()
	if want then
		UiFx.setCandy(button, "Berry")
		if button.Visible then
			UiFx.punch(button, { from = 0.8, peak = 1.15 })
		end
	else
		UiFx.setCandy(button, "Guard")
	end
	setCaption(restCaption(), true)
	syncBadge()
end

-- Кнопка подпрыгивает seconds с (гость во дворе, конец защиты входа).
function DefenceController.Bob(seconds: number)
	local icon = S.icon
	local button = S.button
	if not icon or not button or not button.Visible then
		return
	end
	S.bobUntil = math.max(S.bobUntil, os.clock() + seconds)
	if not S.bobStop then
		S.bobStop = UiFx.bob(icon, { every = BOB_EVERY, lift = 0.12 })
		UiFx.wiggle(button, 8, 2, 0.4)
	end
	task.delay(seconds, function()
		if os.clock() >= S.bobUntil - 1e-3 and S.bobStop then
			local stop = S.bobStop
			S.bobStop = nil
			stop()
		end
	end)
end

-- Перезарядка: вуаль стекает до готовности, «2:59» раз в секунду, пока лист закрыт.
local cooldownTick: (gen: number) -> ()

local function stopCooldown(ready: boolean)
	S.cooldownGen += 1
	local was = S.cooldownOn
	S.cooldownOn = false
	if S.veil then
		S.veil.Visible = false
	end
	if S.veilText then
		S.veilText.Visible = false
	end
	if ready and was and S.button and S.button.Visible then
		-- «ГОТОВ!» на подписи, кольцо, блик; уведомление
		setCaption(TEXTS.Ready, false)
		local caption = S.caption
		if caption then
			UiFx.popIn(caption, { from = 0.3, time = 0.35 })
		end
		UiFx.glowRing(S.button, { color = Palette.Guard.Top, scale = 1.4, thickness = 5 })
		UiFx.shine(S.button, 0.5)
		task.delay(THEFT.ReadyPop, function()
			if not S.cooldownOn and S.caption and S.caption.Text == TEXTS.Ready then
				setCaption(restCaption(), true)
			end
		end)
		NotifyController.Show(TEXTS.Shield.Ready, "shield", AFTER_SHEET)
	end
	syncAlert()
end

function cooldownTick(gen: number)
	if gen ~= S.cooldownGen then
		return
	end
	local left = readyAt() - now()
	if left <= 0 then
		stopCooldown(true)
		return
	end
	local text = S.veilText
	if text then
		local open = S.cards ~= nil and S.cards:IsOpen()
		text.Visible = not open
		if not open then
			text.Text = StealRules.FormatClock(left)
		end
	end
	local step = left - math.floor(left)
	task.delay(if step > 0.02 then step else 1, cooldownTick, gen)
end

local function syncCooldown()
	local left = readyAt() - now()
	if left <= 0 then
		if S.cooldownOn then
			stopCooldown(true)
		end
		return
	end
	if S.cooldownOn and math.abs(readyAt() - S.readyAtShown) < 0.01 then
		return
	end
	S.cooldownGen += 1
	S.cooldownOn = true
	S.readyAtShown = readyAt()
	local veil, drain = S.veil, S.drain
	if veil then
		veil.Visible = true
	end
	if drain then
		local covered = math.clamp(left / CYCLE, 0, 1)
		drain.Offset = Vector2.new(0, 0.5 - covered)
		UiFx.tween(drain, left, { Offset = Vector2.new(0, 0.5) }, Enum.EasingStyle.Linear)
	end
	syncAlert()
	cooldownTick(S.cooldownGen)
end

--------------------------------------------------------------------------------
-- Фишка «🛡️ 0:42»
--------------------------------------------------------------------------------

local function chipShowable(): boolean
	local hud = S.hud
	if not hud or typeof(hud:GetAttribute("IntroAt")) ~= "number" then
		return false
	end
	local banner = hud:FindFirstChild("BaseBanner")
	return not (banner and banner:IsA("GuiObject") and banner.Visible)
end

local chipTick: (gen: number) -> ()

local function hideChip()
	S.chipGen += 1
	local chip = S.chip
	if chip and chip.Visible and S.chipOn then
		UiFx.popOut(chip, { time = 0.2, hide = true })
	elseif chip then
		chip.Visible = false
	end
	S.chipOn = false
	S.chipKind = nil
end

-- Защита входа / новичка кончается через EndingWarn: «Скоро воры смогут красть…», кнопка
-- подпрыгивает (DC-07).
local function endingWarn(kind: string, untilAt: number, left: number)
	if not JOIN_KINDS[kind] or left > SHIELD.EndingWarn or S.warned == untilAt then
		return
	end
	S.warned = untilAt
	NotifyController.Show(TEXTS.Protect.Ending, "shield", AFTER_SHEET)
	DefenceController.Bob(SHIELD.EndingWarn)
end

function chipTick(gen: number)
	if gen ~= S.chipGen then
		return
	end
	local kind, untilAt = protection()
	if not kind or not untilAt then
		hideChip()
		return
	end
	local left = untilAt - now()
	local label = S.chipLabel
	if label then
		label.Text = TextUtil.fill(TEXTS.Chip, { t = StealRules.FormatClock(left) })
		if left <= SHIELD.WarnLast then
			UiFx.flashText(label, Palette.Sun.Top, 0.4)
			if S.chip then
				UiFx.bump(S.chip, CHIP_BUMP, 0.25)
			end
		end
	end
	endingWarn(kind, untilAt, left)
	-- (ровно до смены числа — как строка защит над аквариумом и табличка флага: одно время)
	task.delay(math.max(left - math.floor(left), 0.01), chipTick, gen)
end

local function greet(kind: string, left: number)
	if S.greeted or not JOIN_KINDS[kind] then
		return
	end
	S.greeted = true
	local untilAt = now() + left
	local function text(): string?
		local rest = untilAt - now()
		return if rest >= 1 then TextUtil.fill(TEXTS.Protect[kind], { t = StealRules.FormatClock(rest) }) else nil
	end
	NotifyController.Show(text() or "", "shield", { afterSheet = true, live = text, clock = untilAt })
end

local function syncChip()
	local chip = S.chip
	if not chip then
		return
	end
	local kind, untilAt = protection()
	if not kind or not untilAt or not chipShowable() then
		if S.chipOn then
			hideChip()
		end
		return
	end
	if kind ~= S.chipKind then
		-- щит — сплошная Guard, остальные защиты — стекло с Guard-значком
		UiFx.setCandy(chip, if kind == "shield" then "Guard" else "Glass")
		S.chipKind = kind
	end
	if not S.chipOn then
		S.chipOn = true
		chip.Visible = true
		UiFx.popIn(chip, { from = 0.3, time = 0.35, rotate = -8 })
		greet(kind, untilAt - now())
	else
		UiFx.punch(chip, { from = 0.85, peak = 1.12 })
	end
	S.chipGen += 1
	chipTick(S.chipGen)
end

-- Своя база сменилась: следим за её защитой.
local function bindBase()
	local base = ownBase()
	if base == S.base then
		return
	end
	S.baseTrove:Clean()
	S.base = base
	if base then
		S.baseTrove:Connect(base:GetAttributeChangedSignal("ProtectUntil"), syncChip)
		S.baseTrove:Connect(base:GetAttributeChangedSignal("ProtectKind"), syncChip)
	end
	syncChip()
end

--------------------------------------------------------------------------------
-- Появление кнопки
--------------------------------------------------------------------------------

-- «!» один раз за игру: впервые хватает денег на защиту, которой ещё нет.
local function checkAffordable()
	if S.affordShown or not S.button or not S.button.Visible then
		return
	end
	local cheapest = DefenceCards.Cheapest(player)
	local money = numberAttr(player, "Money") or 0
	if cheapest and money >= cheapest then
		S.affordShown = true
		S.affordBadge = true
		syncBadge()
	end
end

local function refreshVisible()
	local button = S.button
	local hud = S.hud
	if not button or not hud then
		return
	end
	local want = wanted()
	if want and not button.Visible then
		button.Visible = true
		local intro = hud:GetAttribute("IntroAt") :: number
		local gap = UIConfig.Wallet.IntroGap
		local delay = if S.shownOnce then 0 else math.max(0, intro + INTRO_STEPS * gap - os.clock())
		S.shownOnce = true
		UiFx.popIn(button, { from = 0.3, time = 0.4, delay = delay })
		if S.icon then
			UiFx.popIn(S.icon, { from = 0, time = 0.4, delay = delay + 0.12, rotate = -25 })
		end
		syncCooldown()
		syncAlert()
		checkAffordable()
	elseif not want and button.Visible then
		button.Visible = false
		if S.cards then
			S.cards:Close("api")
		end
	end
end

--------------------------------------------------------------------------------
-- Лист
--------------------------------------------------------------------------------

function DefenceController.Toggle(): boolean
	local cards = S.cards
	if not cards then
		return false
	end
	if cards:IsOpen() then
		cards:Close("toggle")
		return true
	end
	local ok = cards:Open()
	if ok then
		if S.affordBadge then
			S.affordBadge = false
			syncBadge()
		end
		if S.veilText then
			S.veilText.Visible = false -- (время перезарядки — на карточке щита)
		end
	elseif S.button then
		UiFx.wiggle(S.button, 7, 2, 0.3)
	end
	return ok
end

function DefenceController.IsOpen(): boolean
	return S.cards ~= nil and S.cards:IsOpen()
end

-- Щит кончил кражу (AlertController, Saved "shield"): «Щит включён» не показывать — ни
-- отложенное, ни то, что придёт в ближайшие MERGE_WAIT с. Сколько с щита осталось.
function DefenceController.TakeShieldToast(): number
	S.shieldTaken = os.clock()
	cancel(S.shieldToast)
	S.shieldToast = nil
	local untilAt = numberAttr(player, "ShieldUntil")
	local left = if untilAt then untilAt - now() else 0
	return if left > 0 then left else SHIELD.Duration
end

function DefenceController.Stats(): { [string]: any }
	return {
		open = DefenceController.IsOpen(),
		alert = S.alert,
		cooldown = S.cooldownOn,
		chip = S.chipOn,
		bob = S.bobStop ~= nil,
		cards = if S.cards then S.cards:Stats() else nil,
	}
end

--------------------------------------------------------------------------------
-- Ответы сервера
--------------------------------------------------------------------------------

local function onDefenceEvent(kind: any, data: any)
	local payload = if type(data) == "table" then data else {}
	if kind == "Shield" then
		cancel(S.shieldWait)
		S.shieldWait = nil
		S.shieldFrom = nil
		local untilAt = if typeof(payload.Until) == "number" then payload.Until else now() + SHIELD.Duration
		local function toast()
			S.shieldToast = nil
			if os.clock() - S.shieldTaken > MERGE_WAIT then
				-- (лист открыт — ждёт его ухода: на «ЗАЩИТА» щит виден на карточке; время — на миг показа
				-- и дальше секунда в секунду с фишкой, clock: F-12)
				local function text(): string?
					local left = untilAt - now()
					return if left >= 1
						then TextUtil.fill(TEXTS.Shield.On, { t = StealRules.FormatClock(left) })
						else nil
				end
				NotifyController.Show(text() or "", "shield", { afterSheet = true, live = text, clock = untilAt })
			end
		end
		cancel(S.shieldToast)
		S.shieldToast = nil
		local hud = S.hud
		if hud and hud:GetAttribute("AlertPhase") ~= nil then
			S.shieldToast = task.delay(MERGE_WAIT, toast) -- (кража кончится щитом — одно уведомление)
		else
			toast()
		end
		if S.cards then
			S.cards:ShieldAnswered(true)
		end
		task.defer(syncCooldown) -- (ShieldReadyAt уже записан: вуаль)
	elseif kind == "Bought" then
		if S.cards then
			S.cards:Bought(payload)
		end
	elseif kind == "Denied" then
		local item = payload.Item
		local text = if typeof(payload.Text) == "string" then payload.Text else ""
		if typeof(item) == "string" and S.cards then
			S.cards:Denied(item)
		else
			cancel(S.shieldWait)
			S.shieldWait = nil
			local from = S.shieldFrom
			S.shieldFrom = nil
			if from then
				UiFx.wiggle(from, 7, 2, 0.35)
			end
			if S.cards then
				S.cards:ShieldAnswered(false)
			end
		end
		if text ~= "" then
			NotifyController.Show(text, "warning")
		end
	end
end

--------------------------------------------------------------------------------
-- Запуск
--------------------------------------------------------------------------------

function DefenceController:Start(hud: ScreenGui)
	S.hud = hud
	local column = hud:WaitForChild("RightButtons")
	local button = column:WaitForChild("DefenceButton") :: GuiButton
	S.button = button
	S.caption = button:FindFirstChild("Caption") :: TextLabel?
	S.icon = button:FindFirstChild("Icon") :: GuiObject?
	S.badge = button:FindFirstChild("Badge") :: GuiObject?
	local veil = button:FindFirstChild("Cooldown") :: GuiObject?
	S.veil = veil
	S.drain = if veil then veil:FindFirstChild("Drain") :: UIGradient? else nil
	S.veilText = button:FindFirstChild("CooldownText") :: TextLabel?
	if veil then
		veil.Visible = false
	end
	if S.veilText then
		S.veilText.Visible = false
	end
	if S.badge then
		S.badge.Visible = false
	end
	button.Visible = false
	local badgeFrame = hud:WaitForChild("Status"):WaitForChild("BaseBadge")
	local chip = badgeFrame:WaitForChild("ShieldChip") :: GuiObject
	S.chip = chip
	S.chipLabel = chip:FindFirstChild("Label") :: TextLabel?
	chip.Visible = false

	S.cards = DefenceCards.new(hud, hud:WaitForChild("DefencePanel") :: GuiObject, {
		onShield = function(from: GuiObject)
			DefenceController.ActivateShield(from)
		end,
	})

	UiFx.press(button, { sound = "click" })
	button.Activated:Connect(function()
		if S.alert then
			DefenceController.ActivateShield(button) -- одно нажатие — щит, без листа
			return
		end
		DefenceController.Toggle()
	end)

	Net.Event("DefenceEvent").OnClientEvent:Connect(onDefenceEvent)
	player.AttributeChanged:Connect(function(name: string)
		if name == "BaseIndex" then
			bindBase()
			refreshVisible()
		elseif name == "DataMode" then
			refreshVisible()
		elseif name == "ShieldReadyAt" then
			syncCooldown()
			syncAlert()
		elseif name == "Stealing" then
			syncAlert()
		elseif name == "Money" or name == "HasDog" or name == "HasAlarm" or name == "LockLevel" then
			checkAffordable()
		end
	end)
	hud.AttributeChanged:Connect(function(name: string)
		if name == "AlertPhase" then
			syncAlert()
		elseif name == "IntroAt" then
			refreshVisible()
			syncChip()
		end
	end)
	local banner = hud:FindFirstChild("BaseBanner")
	if banner and banner:IsA("GuiObject") then
		banner:GetPropertyChangedSignal("Visible"):Connect(syncChip)
	end
	bindBase()
	refreshVisible()
	syncCooldown()
	syncChip()
end

return DefenceController
