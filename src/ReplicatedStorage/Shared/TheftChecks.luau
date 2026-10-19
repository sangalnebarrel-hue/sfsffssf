--!strict
--[[
	TheftChecks — проверки начала кражи (Этап 4, docs/stage4_design.md §4.3; BE-28): упорядоченная
	таблица строк над простой структурой view. Сервер (StealService, PromptButtonHoldBegan) и
	клиент (TheftController: прятать кнопку «Украсть», StealRules.CanStealView) идут по ОДНОЙ
	таблице — фильтр клиента и отказ сервера не расходятся. Чистый модуль: без состояния, без
	game и Instance; каждую строку можно проверить без сервера (tests/stage4_rules).

	  TheftChecks.Check(view, clientOnly?) -> (reason?, quiet?, left?)
	      первая провалившаяся строка по порядку: reason — её причина (ключ
	      StealConfig.Texts.Denied или «тихая» причина из TheftChecks.Silent: сервер не отвечает
	      вовсе); quiet — та же причина уже была отказом меньше Limits.DeniedEvery с назад
	      (view.LastReason / LastAt / Now: сервер шлёт Denied с Quiet = true — без текста, но
	      клиент узнаёт, какое кольцо погасить); left — сколько секунд ждать (для {t} в тексте:
	      cooldown, ожидание на базе, защита, new). Всё прошло — nil. clientOnly — только строки с
	      Client = true (то, что клиент знает из атрибутов).
	  TheftChecks.Rows      -- строки по порядку: { Id, Client, Reasons }; 17 строк (§4.3)
	  TheftChecks.Silent    -- причины без ответа: prompt, repeat, bucket, self
	  TheftChecks.Fields    -- все поля view (сервер заполняет каждое: Missing)
	  TheftChecks.Missing(view) -> { string }   -- каких полей нет (тесты StealService)

	Поля view (nil — «не знаю» — строку пропускает: клиент знает не всё; сервер заполняет все,
	TheftChecks.Missing это ловит):
	  1  Known          false — нажата не кнопка кражи                          → prompt (тихо)
	  2  Repeat         true — вор уже держит именно эту кнопку (двойное нажатие) → repeat (тихо)
	  3  Bucket         false — лимит начал (Limits.StartBurst / StartRate) пуст  → bucket (тихо)
	  4  Own            true — кнопка на своей базе                     (клиент) → self (тихо)
	  5  ThiefWritable  false — данные вора ещё грузятся (CanWrite)              → loading
	  6  ThiefMounted   false — у вора нет своей подключённой базы      (клиент) → nobase
	  7  VictimReady    false — хозяин не CanWrite или его садок не на этой базе → busy
	  8  Alive, Distance  вор жив и тот же персонаж; HRP от точки кнопки (3D) не дальше
	                    Prompt.MaxDistance + Prompt.Slack                       → far
	  9  Stealing       true — вор уже крадёт                            (клиент) → stealing
	  10 CooldownLeft, TagLeft  > 0 — вор ждёт (после кражи / срывов) или эта база закрыта для него
	                    (TagKind — почему: "tagged" — хозяин поймал, "shielded" — хозяин включил щит
	                    против его кражи, "wary" — Limits.BaseFails срывов на ней; нет — "tagged")
	                                                    (клиент) → cooldown / tagged / shielded / wary
	  11 ProtectLeft, ProtectKind  > 0 — база под защитой (shield | join | newbie | after | rest)
	                                                                     (клиент) → её вид
	  12 BaseTheft      true — на этой базе уже крадут                  (клиент) → taken
	  13 OwnerDistance  хозяин ближе Tag.Range studs (по горизонтали)            → owner
	  14 VictimActive   у хозяина активных рыб меньше Limits.MinFishToRob (клиент) → few
	  15 ThiefIncome10, VictimIncome10  доход вора (десятые $/с) ≥ RichMin × 10 и больше
	                    RichRatio × доход хозяина (RichRatio = 0 — выключено)   (клиент) → weak
	  16 FishMissing    true — рыбы нет / не та (FishUid) / спит                 → missing
	     FishTaken      true — её крадут (Steal) или она «в пути» (Escrow)       → fresh
	     FreshLeft      > 0 — поймана меньше Limits.FreshCatch с назад  (клиент) → new
	  17 Placeable      false — в садке вора ей нет места: свободной витрины нет, а она не
	                    сильнее его слабейшей (StealRules.CanPlace)     (клиент) → full
	  LastReason, LastAt, Now — для quiet (см. выше). ProtectKind и TagKind — только вместе со своим
	  *Left > 0 (Missing их не требует).
	Сервер берёт жетон лимита (строка 3) только после строк 1–2: сначала Check({ Known, Repeat }),
	потом Take и полный view — двойное нажатие на ту же кнопку жетон не тратит (BE-17).
	Число Distance / OwnerDistance — studs; *Left — секунды; доходы — десятые $/с
	(TankRules.Income10).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StealConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("StealConfig"))

export type View = {
	Known: boolean?,
	Repeat: boolean?,
	Bucket: boolean?,
	Own: boolean?,
	ThiefWritable: boolean?,
	ThiefMounted: boolean?,
	VictimReady: boolean?,
	Alive: boolean?,
	Distance: number?,
	Stealing: boolean?,
	CooldownLeft: number?,
	TagLeft: number?,
	TagKind: string?,
	ProtectLeft: number?,
	ProtectKind: string?,
	BaseTheft: boolean?,
	OwnerDistance: number?,
	VictimActive: number?,
	ThiefIncome10: number?,
	VictimIncome10: number?,
	FishMissing: boolean?,
	FishTaken: boolean?,
	FreshLeft: number?,
	Placeable: boolean?,
	LastReason: string?,
	LastAt: number?,
	Now: number?,
}

-- Строка: Test(view) → причина при провале, nil — прошла; Left(view, reason) — сколько секунд ждать
-- (для {t}) при этой причине, nil — ждать нечего.
export type Row = {
	Id: string,
	Client: boolean,
	Reasons: { string },
	Test: (view: View) -> string?,
	Left: ((view: View, reason: string) -> number?)?,
}

local PROMPT = StealConfig.Prompt
local LIMITS = StealConfig.Limits
local TAG = StealConfig.Tag

local function positive(x: number?): boolean
	return type(x) == "number" and x > 0
end

-- Почему база закрыта для вора (строка «wait», TagKind); другое или nil — "tagged".
local BASE_WAITS: { [string]: boolean } = { tagged = true, shielded = true, wary = true }

local Rows: { Row } = {
	{
		Id = "prompt",
		Client = false,
		Reasons = { "prompt" },
		Test = function(v: View): string?
			return if v.Known == false then "prompt" else nil
		end,
	},
	{
		Id = "repeat",
		Client = false,
		Reasons = { "repeat" },
		Test = function(v: View): string?
			return if v.Repeat == true then "repeat" else nil
		end,
	},
	{
		Id = "bucket",
		Client = false,
		Reasons = { "bucket" },
		Test = function(v: View): string?
			return if v.Bucket == false then "bucket" else nil
		end,
	},
	{
		Id = "self",
		Client = true,
		Reasons = { "self" },
		Test = function(v: View): string?
			return if v.Own == true then "self" else nil
		end,
	},
	{
		Id = "loading",
		Client = false,
		Reasons = { "loading" },
		Test = function(v: View): string?
			return if v.ThiefWritable == false then "loading" else nil
		end,
	},
	{
		Id = "nobase",
		Client = true,
		Reasons = { "nobase" },
		Test = function(v: View): string?
			return if v.ThiefMounted == false then "nobase" else nil
		end,
	},
	{
		Id = "busy",
		Client = false,
		Reasons = { "busy" },
		Test = function(v: View): string?
			return if v.VictimReady == false then "busy" else nil
		end,
	},
	{
		Id = "far",
		Client = false,
		Reasons = { "far" },
		Test = function(v: View): string?
			if v.Alive == false then
				return "far"
			end
			local d = v.Distance
			if type(d) == "number" and not (d <= PROMPT.MaxDistance + PROMPT.Slack) then
				return "far" -- (и NaN: не число — не рядом)
			end
			return nil
		end,
	},
	{
		Id = "stealing",
		Client = true,
		Reasons = { "stealing" },
		Test = function(v: View): string?
			return if v.Stealing == true then "stealing" else nil
		end,
	},
	{
		Id = "wait",
		Client = true,
		Reasons = { "cooldown", "tagged", "shielded", "wary" },
		Test = function(v: View): string?
			if positive(v.CooldownLeft) then
				return "cooldown"
			elseif positive(v.TagLeft) then
				local kind = v.TagKind
				return if type(kind) == "string" and BASE_WAITS[kind] then kind else "tagged"
			end
			return nil
		end,
		Left = function(v: View, reason: string): number?
			return if reason == "cooldown" then v.CooldownLeft else v.TagLeft
		end,
	},
	{
		Id = "protect",
		Client = true,
		Reasons = { "shield", "join", "newbie", "after", "rest" },
		Test = function(v: View): string?
			if positive(v.ProtectLeft) then
				local kind = v.ProtectKind
				return if type(kind) == "string" and StealConfig.Texts.Denied[kind] then kind else "shield"
			end
			return nil
		end,
		Left = function(v: View, _reason: string): number?
			return v.ProtectLeft
		end,
	},
	{
		Id = "taken",
		Client = true,
		Reasons = { "taken" },
		Test = function(v: View): string?
			return if v.BaseTheft == true then "taken" else nil
		end,
	},
	{
		Id = "owner",
		Client = false,
		Reasons = { "owner" },
		Test = function(v: View): string?
			local d = v.OwnerDistance
			return if type(d) == "number" and d <= TAG.Range then "owner" else nil
		end,
	},
	{
		Id = "few",
		Client = true,
		Reasons = { "few" },
		Test = function(v: View): string?
			local n = v.VictimActive
			return if type(n) == "number" and n < LIMITS.MinFishToRob then "few" else nil
		end,
	},
	{
		Id = "weak",
		Client = true,
		Reasons = { "weak" },
		Test = function(v: View): string?
			local thief, victim = v.ThiefIncome10, v.VictimIncome10
			if LIMITS.RichRatio <= 0 or type(thief) ~= "number" or type(victim) ~= "number" then
				return nil
			end
			if thief >= LIMITS.RichMin * 10 and thief > LIMITS.RichRatio * victim then
				return "weak"
			end
			return nil
		end,
	},
	{
		Id = "fish",
		Client = true,
		Reasons = { "missing", "fresh", "new" },
		Test = function(v: View): string?
			if v.FishMissing == true then
				return "missing"
			elseif v.FishTaken == true then
				return "fresh"
			elseif positive(v.FreshLeft) then
				return "new"
			end
			return nil
		end,
		Left = function(v: View, reason: string): number?
			return if reason == "new" then v.FreshLeft else nil -- (missing / fresh: ждать нечего)
		end,
	},
	{
		Id = "full",
		Client = true,
		Reasons = { "full" },
		Test = function(v: View): string?
			return if v.Placeable == false then "full" else nil
		end,
	},
}

local Silent: { [string]: boolean } = {
	prompt = true,
	["repeat"] = true,
	bucket = true,
	self = true,
}

local Fields = {
	"Known",
	"Repeat",
	"Bucket",
	"Own",
	"ThiefWritable",
	"ThiefMounted",
	"VictimReady",
	"Alive",
	"Distance",
	"Stealing",
	"CooldownLeft",
	"TagLeft",
	"TagKind",
	"ProtectLeft",
	"ProtectKind",
	"BaseTheft",
	"OwnerDistance",
	"VictimActive",
	"ThiefIncome10",
	"VictimIncome10",
	"FishMissing",
	"FishTaken",
	"FreshLeft",
	"Placeable",
	"Now",
}
-- (ProtectKind / TagKind — только вместе с ProtectLeft / TagLeft > 0; LastReason / LastAt — только
-- после отказа)
local OPTIONAL = { ProtectKind = true, TagKind = true }

local TheftChecks = {
	Rows = Rows,
	Silent = Silent,
	Fields = Fields,
}

function TheftChecks.Check(view: View, clientOnly: boolean?): (string?, boolean?, number?)
	for _, row in Rows do
		if clientOnly and not row.Client then
			continue
		end
		local reason = row.Test(view)
		if reason then
			local left = if row.Left then row.Left(view, reason) else nil
			if Silent[reason] then
				return reason, nil, nil
			end
			local quiet = view.LastReason == reason
				and type(view.Now) == "number"
				and type(view.LastAt) == "number"
				and view.Now - view.LastAt < LIMITS.DeniedEvery
			return reason, if quiet then true else nil, left
		end
	end
	return nil, nil, nil
end

function TheftChecks.Missing(view: View): { string }
	local missing = {}
	local raw = view :: any
	for _, field in Fields do
		if raw[field] == nil and not OPTIONAL[field] then
			table.insert(missing, field)
		end
	end
	return missing
end

return TheftChecks
