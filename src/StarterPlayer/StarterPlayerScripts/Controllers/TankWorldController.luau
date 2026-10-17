--!strict
--[[
	TankWorldController — садок в мире (Этап 3, только этот клиент): рыбы в витринах дворов баз,
	надписи над витринами и над большим аквариумом, слово садка над ведром у места рыбалки, всплески
	и искры событий витрин, слово «РЫНОК +50%!» над рынком острова. Числа — TankConfig.Display /
	Pier, данные — атрибуты витрин и садка (RemoteNames, «Состояние садка и денег»). Новых деталей
	на сервере нет: рыбы — клиентские копии (MapConfig.PartBudget.RuntimeReserve.TankFish).
	ЗАГЛУШКА (волна 0): Start ничего не делает. Реализация — волна 1 (scratchpad design.md, §5.3;
	помощник TankDisplay).

	Что делает:
	  • Расстояние с запасом: цепочка task.delay раз в Display.CheckEvery секунд (без соединения)
	    меряет от камеры; базы, чей Tank.Glass ближе Display.Range, получают рыб (не больше
	    BuildPerCheck моделей за проверку), дальше DropRange — убираются (у каждой базы свой Trove).
	    Новая база читает все витрины один раз, дальше витрина обновляется ТОЛЬКО по своему Event
	    (одно отложенное task.defer на витрину перечитывает все поля: при "swap" State остаётся
	    "fish", меняется FishUid).
	  • Рыба: копия ReplicatedStorage.Assets.Fish[FishId][Mutation или "Normal"] (незнакомая
	    мутация — "Normal"), масштаб min(MaxScale, Fit / длинная сторона), центр ГАБАРИТА — на
	    Display.FishPoint (Body смещён до 0.88), голова по ±X витрины (чередуется по SlotIndex % 4
	    < 2), поворот Yaw° к проходу; CanCollide, CanQuery, CanTouch, CastShadow — false; атрибуты
	    FishId, Rarity, Mutation, Kg, Value (радужные переливаются сами: тег RainbowFish); все
	    детали сварены с заякоренным Body.
	  • Тихая жизнь — только зацикленные твины (без покадрового Lua): ближе LifeRange — один твин
	    CFrame корня (покачивание ±0.12 stud и ±6°, Sine InOut, 2.4–3.2 с, Reverses, бесконечно,
	    случайная фаза); дальше — твины сняты. Рыба не «шлёпает».
	  • Надпись витрины FxTankTag — BillboardGui над стеклом (FishPoint + (0, 3.6, 0), ниже потолка
	    галереи), ≈ 5.5 × 1.8 studs, MaxDistance TagRange, без света и AlwaysOnTop: «+$4/с»
	    (BillboardGreen) и «$45 ▲» / «$135 МАКС» (BillboardYellow), стиль STYLE §3 «надписи в мире»;
	    значения — раз в секунду и только ближе TagRange.
	  • Надпись садка FxTankSign над Tank.Glass (выше таблички «АКВАРИУМ»), MaxDistance SignRange:
	    «+$42/с» крупно зелёным, «🐠 4/6» мельче белым — из атрибутов садка; у свободной базы нет.
	  • Слово у ведра FxPierTank — ТОЛЬКО своя база: BillboardGui на клиентском Attachment над
	    Platform.Bucket, ≈ 4 × 1.4 studs, MaxDistance Pier.Range: «🐠 4/6» и «+$42/с»
	    (BillboardGreen) из атрибутов игрока. Спрятано, пока FishingState — Bite или Reeling, пока
	    у HUD CounterHold и пока свой персонаж держит HeldFish. Прилёт "stored" / "replaced" (снят
	    CounterHold) — один всплеск Emit у края ведра и «удар» слова; ближе PopRange к ведру, при
	    доходе > 0 и видимом слове раз в PopEvery с всплывает «+$13» (твин 1.2 с). Кнопки
	    ProximityPrompt у ведра нет (тап в 5 studs от точки рыбалки попал бы в экран рыбалки).
	  • События витрин (базы ближе EventRange): "in" — брызги и искры (Emit на временном
	    Attachment над ВЕРХОМ витрины, не внутри стекла), вспышка LightBar, надпись выскакивает;
	    "sold" / "swap" — рыба сжимается за 0.25 с, золотые искры, «+$45»; "mount" — тихо, без
	    эффектов. Не больше 2 ParticleEmitter на игрока.
	  • Кнопки "TankPrompt" чужих баз — Enabled = false только на этом клиенте (сервер всё равно
	    проверяет хозяина). Над рынком острова — «РЫНОК +50%!» (BillboardYellow, MaxDistance 200);
	    "Sold" у ларька — горсть монет у его весов.
	Атрибуты витрин требуют StreamingEnabled = false (tools/build.luau). Стекло с прозрачностью
	прячет частицы и надписи за собой — эффекты и надписи только над стеклом или снаружи.

	API:
	  TankWorldController:Start(hud)
]]

local TankWorldController = {}

function TankWorldController:Start(_hud: ScreenGui) end

return TankWorldController
