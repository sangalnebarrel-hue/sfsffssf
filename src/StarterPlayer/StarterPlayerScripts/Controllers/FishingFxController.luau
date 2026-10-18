--!strict
--[[
	FishingFxController — рыбалка в мире, для ВСЕХ игроков (и для себя), только на клиенте.
	Стиль — tools/builder/gui/STYLE.md §3 «World FX» (цвета — UIConfig, тайминги и лимиты —
	FishingConfig.LeapTime, FishingConfig.Fx и FishingRules.HoldFishTime).

	Поплавки и лески. Клиент следит за атрибутами каждого игрока (их ставит FishingService):
	FishingState, BobberTarget, CastTime, RodId. Когда FishingState уходит из "Idle", клиент
	клонирует поплавок его удочки (ReplicatedStorage.Assets.Bobbers.<RodId>) в папку
	Workspace.FishingFx и натягивает леску (Beam) от кончика удочки (Handle.TipAttachment удочки
	в руке персонажа) до поплавка (Root.LineAttachment).
	  • Поплавок — копия в BOBBER_SCALE раз крупнее шаблона (с пирса до него 30–40 studs: на
	    телефоне маленький не виден; свой — в OWN_BOBBER_SCALE раз, на него смотрят всю рыбалку).
	    Точка привязки (pivot) копии — по-прежнему FloatDepth над ватерлинией, как у шаблона.
	    Свой поплавок — с белым контуром (Highlight «OwnGlow»).
	  • Полёт: дугой от кончика удочки к BobberTarget (+ FloatDepth вверх — тогда ватерлиния
	    поплавка как раз на воде) за FishingConfig.CastFlightTime, кувыркаясь (2 оборота). Время —
	    от CastTime по workspace:GetServerTimeNow(), поэтому у всех клиентов поплавок летит
	    одинаково. CastTime — на FishingConfig.CastWindUp позже заброса: до него поплавок висит
	    на живом кончике удочки и ходит с ней (замах рыбака — FisherAnimController; свой у самой
	    камеры — полупрозрачный, иначе закрыл бы пол-экрана), в CastTime срывается. Увидели заброс позже, чем за Fx.LaunchGuard до срыва (медленная сеть), —
	    срыв через LaunchGuard, полёт короче, приводнение в то же время. С прямого взмаха
	    (FisherPoses.Timing.Swing до срыва) кончик удочки чертит белый хлёсткий след (Trail «Whip»
	    на Handle, гаснет через FX.WhipAfter после срыва); с мига срыва за поплавком — искрящийся
	    след (Trail, жёлтый → белый) и свист, леска тянется за ним дугой (FishingLine).
	    Приводнился — «плюх»: брызги, низкий столбик воды, 3 круга, звук повыше, и поплавок
	    ныряет на FX.Plop studs, выныривает с перелётом и закачивается (пружина FX.PlopHz).
	  • "Waiting" — покачивается на воде, леска провисает и «дышит» (слабина); раз в
	    Fx.RippleEvery секунд — круг (у рыбаков дальше Fx.AmbientRange — без кругов). Под водой —
	    тень рыбы (FishShadow): приплывает издалека, кружит и присматривается к поплавку. Nibble() —
	    своя «примерка» рыбы: тень бросается к поплавку и тычет его, поплавок заметно
	    притапливается, круг, капли и над ним на миг «?» (как «?» над кнопкой).
	  • "Bite" — рывками ныряет под воду (BiteDip), тень бросается под него и дёргает прочь; на
	    каждом рывке брызги, на каждом втором — круг; леска провисает и натягивается рывками; над поплавком прыгает и пульсирует «!» (жёлто-оранжевый значок). Свой «!» крупный,
	    виден сквозь стены, вокруг кружат звёздочки, контур поплавка мигает жёлтым (2,5 Гц);
	    чужой «!» меньше, без звёздочек, не сквозь стены и не дальше ALERT_OTHER_DISTANCE studs.
	  • "Reeling" — мечется из стороны в сторону и подтягивается к рыбаку (свой — рывком на
	    каждое попадание в мини-игре, "Zone"; чужой — медленно, попаданий не видно), за ним
	    пенный след по воде (Trail «Wake»), брызги и круги; тень рыбы под ним (у своей —
	    крупнее с редкостью, FX.ShadowScale) мечется в такт и сверкает боком; леска натянута,
	    дрожит (FishingLine: ≈13 Гц вбок) и пульсирует толщиной и цветом. Подсекли — леска
	    вспыхивает белым.
	  • снова "Idle" — быстро сматывается к удочке и исчезает вместе с леской; тень уплывает.
	Каждый кадр обновляются только поплавки, которые сейчас в воде или сматываются.

	Камера своего рыбака: пока своя рыбалка «на экране» (FishingState не "Idle", или поплавок
	ещё сматывается, или рыба в прыжке или над головой) Humanoid.CameraOffset плавно уходит
	в FX.CameraOffset (вправо и вверх): рыбак сдвигается левее центра экрана, а поплавок
	(он падает правее, FishingConfig.CastSide) — правее его головы, не за ней. Когда над
	головой своя рыба и открылась карточка улова (HUD.Fishing.CatchCard, она прячет сдвиг), —
	ещё чуть выше (FX.TrophyCamera, и ещё на FX.TrophyLift того, на сколько рыба выросла вверх,
	атрибут Scale): после карточки рыба и табличка не задевают счётчик улова.
	Потом камера плавно возвращается. FieldOfView не трогаем (это UiFx.fovPunch), UiFx.cameraShake
	добавляется поверх.

	Улов и потеря — атрибут FishFx (формат — шапка RemoteNames; сервер ставит его ДО "Idle",
	поэтому поплавок ещё на воде):
	  • caught — у поплавка всплеск, столб воды (Beam) и круги (у мифической — ещё радужная
	    волна), рыба (копия Assets.Fish.<Id>.<мутация>) выпрыгивает из воды и, кувыркаясь, с
	    искрящимся следом цвета редкости летит за LeapTime дугой (выгнутой вбок от камеры,
	    с зависанием на вершине, обороты кончаются к Fx.LeapSpinEnd — на вершине она боком)
	    точно туда, где сервер повесит её над головой рыбака (FishingService.holdFish);
	    поплавок на крючке летит с ней; в прыжке рыба гнётся и бьёт хвостом (FishLife.leapPose)
	    и растёт — из воды уже крупнее настоящей, к концу прыжка как над головой (атрибут Scale
	    у HeldFish, FishingConfig.HeldScale),
	    с неё капает вода (≤ 12 капель-шариков, исчезают до передачи). Тень рыбы исчезает (она
	    теперь в воздухе). В кадр, когда долетела СВОЯ рыба, срабатывает сигнал
	    OwnFishLanded (карточка улова открывается по нему). Копия исчезает в тот кадр, когда
	    появилась серверная HeldFish (пришла раньше — прячется до конца прыжка; не пришла за
	    Fx.HandoffWait — копия исчезает сама). Над головой — короткий чёткий удар в точке рыбы:
	    маленький белый шар, «звезда» тонких лучей цвета редкости (BillboardGui «Burst») и
	    тонкое кольцо-ореол лицом к камере — никакой заливки кадра. Рыба над головой ЖИВЁТ на
	    каждом клиенте (FishLife): покачивается, виляет хвостом и время от времени бьётся
	    (сварки HoldWeld и хвоста — только у себя, сервер не трогаем; табличка не трясётся); над
	    любой рыбой — табличка в духе надписей образца над миром (UI v5 «Симулятор»: без плашки,
	    буквы Montserrat Heavy с тёмной обводкой; у редкой и выше — слово редкости ЗАГЛАВНЫМИ в её
	    цветах, у всех — название белым, мутация в её цвете, цена наклонными жёлтыми
	    цифрами; размер — studs + пиксели
	    NAMEPLATE_STUDS / NAMEPLATE_PIXELS: вблизи растёт с миром, издали не меньше пикселей),
	    у редкой рыбы и выше — искры цвета редкости, у рыбы с мутацией — искры
	    цветов мутации (свет PointLight — только у своей рыбы, v3 fix F9: подвижный свет
	    дорого пересчитывать), пока рыба над головой (FishingRules.HoldFishTime —
	    на ≈3 с дольше карточки улова: после неё свой трофей ещё виден). Чужая табличка — над
	    рыбой, выскакивает сразу; своя — сбоку, справа от рыбы (над ней — заголовок и карточка
	    улова своего экрана; справа до кнопок HUD меньше 16 px — слева или меньше, fitOwnPlate:
	    Этап 3, «САДОК» на высоте рыбы) и ждёт, пока улов на экране (у HUD атрибут CounterHold): под
	    заголовком она повторяла бы его слово, из-за карточки торчала бы готовая цена, пока та
	    считает; выскакивает на «повторе» трофея (ReplayOwnTrophy), а не было его — через
	    PLATE_AFTER_CARD после того, как счётчик отпустили. Рыбу убрали — табличка на её месте
	    «выдыхает» и тает за PLATE_OUT (без рыбы не висит).
	    Легендарная и мифическая — ещё столб света (неоновая сердцевина + лучи Beam), конфетти и
	    волна по земле вокруг рыбака (свой столб — через FX.OwnPillarDelay после удара и с
	    тонкой сердцевиной: виден за лучами заголовка, но не заливает кадр). Чужой
	    столб живёт дольше (Fx.PillarTimeOther), издалека шире (не уже ~25 px с соседнего пирса)
	    и выше (PILLAR_SKY: луч уходит за верх экрана с любого пирса) — его видно через всю
	    лагуну; вблизи он начинается над табличкой рыбака (не режет рыбу и надпись). Объявление
	    о такой рыбе (FishingService) приходит в тот же миг, а сигнал OtherTrophy говорит HUD,
	    где столб (NotifyController показывает значок у края экрана, если столба не видно).
	  • lost — леска вспыхивает красным и провисает, поплавок подскакивает и шлёпается обратно
	    (потом сматывается), всплеск, столбик воды и круги, и рыбка, махнув хвостом, уходит под
	    воду прочь от рыбака; тень уплывает прочь и тает.

	Бюджет (STYLE.md §4): все детали эффектов только на клиенте (Anchored, без столкновений,
	запросов и теней) и удаляются, когда эффект кончился; не больше Fx.MaxEmitters
	ParticleEmitter'ов на одного рыбака (лишний уступает место: сначала искры над рыбой, потом
	конфетти); дальше Fx.Range studs от своего персонажа — ничего, кроме столба света.
	Круги — SurfaceGui на детали сразу конечного размера (растут рамки внутри, а не холст), не
	больше Fx.MaxRings спокойных кругов на рыбака; «оснастка» круга (деталь + SurfaceGui + рамки)
	берётся из пула рыбака и возвращается в него, когда круг погас (не больше RING_POOL штук, v3
	fix F5: не 9 новых Instance на каждый круг). Далёкие поплавки (дальше Fx.Range) — без лески
	(Beam выключен), и переставляются не каждый кадр, а раз в FAR_PIVOT с (или сразу при смене
	состояния) — v3 fix F7. Покадрово (одно соединение RenderStepped на
	всё, отключается, когда ничего не идёт) — поплавки, прыжки, ныряния, столбы воды и света;
	круги, искры, ореол, табличка и конфетти — TweenService, task.delay и ParticleEmitter,
	без соединений.
	  v3 (замерено в tests/fishing_fx.test.luau): тень — 2 детали SmoothPlastic и один
	  BulkMoveTo за кадр на поплавок (своя всегда, чужие — ближе Fx.AmbientRange); леска — ≤ 6
	  записей свойств Beam за кадр; хлыст — 1 Trail + 1 Attachment на ≈0,5 с; прыжок — один
	  BulkMoveTo всех деталей рыбы (≤ 30) за кадр ≈1 с и ≤ 12 капель; живая рыба над головой —
	  эффект в общем RenderStepped: ближе FX.LifeNear — 1 запись HoldWeld.C0 + по записи C0 на
	  каждую гнущуюся деталь (хвост, плавники) за кадр, до FX.LifeRange — одна запись через
	  кадр, дальше — ничего (таймер раз в FX.LifePoll с, без соединения). Новые соединения: на
	  игрока CharacterAdded, на персонажа ChildAdded (появилась HeldFish), один слушатель
	  FishingState (редкость своей рыбы для тени). В покое — ни одного покадрового соединения.

	Радужные рыбы: модели с тегом "RainbowFish" (CollectionService), кроме шаблонов в
	ReplicatedStorage. Детали с атрибутами RainbowU / RainbowV переливаются:
	Color3.fromHSV((U·0.85 + t·0.35) % 1, 0.72, 0.55 + 0.45·V), около 20 раз в секунду — пока
	модель видна: в мире не дальше Fx.Range от персонажа или камеры (в том числе рыба в прыжке)
	или в своём интерфейсе (ViewportFrame карточки улова). Рыба в руках персонажа (HeldFish —
	внутри модели с Humanoid) перекрашивается реже: не чаще RAINBOW_HELD_RATE раз в секунду,
	тон — ступенями (RAINBOW_STEPS на круг; ступень не сменилась — не пишем) и только ближе
	FX.LifeNear: смена Color у детали персонажа пересобирает его общий меш (v3 fix F3).
	Соединение Heartbeat есть, только пока такие модели есть.

	Вышедший игрок убирается целиком (его поплавок, леска, все эффекты и подписки).

	API (для FishingController и тестов):
	  FishingFxController.OwnFishLanded   -- Signal (ReplicatedStorage.Shared.Util.Signal):
	      (rarity: string, worldPosition: Vector3) — СВОЯ пойманная рыба долетела до места над
	      головой (worldPosition — центр рамки рыбы). Ровно один раз на каждый свой улов: в кадр
	      приземления; если прыжка нет (нет персонажа или модели) — сразу (task.defer, с точкой
	      над головой); если прыжок оборвался (умер) — в этот момент. Подписываться заранее
	      (на Start), а не по событию "Caught": без прыжка сигнал может прийти раньше него.
	  FishingFxController.Nibble() -> boolean
	      -- «поклёвка-примерка» только на этом клиенте: свой поплавок (если он на воде и ждёт
	      -- поклёвку) притапливается на NIBBLE_DIP stud за NIBBLE_TIME / 2 с и всплывает,
	      -- вокруг — круг, капли и «?» (NibbleMark). false — поплавка нет / не "Waiting" (ничего).
	  FishingFxController.GetBobber(player) -> Model?          -- поплавок игрока (если есть)
	  FishingFxController.GetEffects(player) -> { Instance }   -- детали эффектов рыбака
	  FishingFxController.CountEmitters(player) -> number      -- его ParticleEmitter'ы сейчас
	  FishingFxController.ReplayOwnTrophy() -> boolean
	      -- своя рыба над головой ещё раз «вспыхивает» (FishingController — когда карточка улова
	      -- закрылась и в счётчике встал «+1»): шар, ореол, искры, своя табличка выскакивает
	      -- (уже видна — «подпрыгивает»), звон, у легендарной и мифической — короткий столб света
	      -- (TROPHY_PILLAR_TIME); на невысоком экране (телефон) — без столба, ореол меньше и
	      -- искр больше: столб вставал бы за счётчиком улова. false — своей HeldFish нет (ничего).
	  FishingFxController.OtherTrophy   -- Signal: (player: Player, basePosition: Vector3,
	      rarity: string) — у ДРУГОГО рыбака встал столб света легендарной / мифической рыбы
	      (basePosition — земля под ним; горит Fx.PillarTimeOther[rarity] с). Своему не приходит.
	  FishingFxController.TrophyReplayed -- Signal: () — свой трофей «вспыхнул» ещё раз
	      (ReplayOwnTrophy вернул true); FisherAnimController празднует: присел, подпрыгнул,
	      качает рыбу руками, поворачивается с ней.
	  FishingFxController.KickHeldFish(player, power?) -> boolean
	      -- рыба над головой игрока шлёпает хвостом сейчас (FishLife.kick; FisherAnimController —
	      -- «показ» трофея: рывок руками в тот же кадр). false — она сейчас не живёт.
	  FishingFxController.GetBobberDip(player) -> number
	      -- насколько поплавок сейчас притоплен рыбой, 0..1 (рывки поклёвки BiteDip, своя
	      -- «примерка» Nibble); FisherAnimController дёргает кончик удочки вместе с ним.
	Кончик удочки (Handle.TipAttachment) гнёт FisherAnimController (FisherRod двигает его CFrame
	вместе с изгибом) — поплавок и леска каждый кадр берут его живую позицию.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local FishingConfig = require(Config:WaitForChild("FishingConfig"))
local MapConfig = require(Config:WaitForChild("MapConfig"))
local RodConfig = require(Config:WaitForChild("RodConfig"))
local UIConfig = require(Config:WaitForChild("UIConfig"))
local FishingRules = require(Shared:WaitForChild("FishingRules"))
local Net = require(Shared:WaitForChild("Net"))
local Util = Shared:WaitForChild("Util")
local Signal = require(Util:WaitForChild("Signal"))
local Trove = require(Util:WaitForChild("Trove"))
-- Помощники (модули, не контроллеры): живая рыба, тень, леска; тайминги броска рыбака; место
-- своей таблички трофея у кнопок HUD (FishingLayout.plateFit).
local FishLife = require(script.Parent:WaitForChild("FishLife"))
local FishingLayout = require(script.Parent:WaitForChild("FishingLayout"))
local FishShadow = require(script.Parent:WaitForChild("FishShadow"))
local FishingLine = require(script.Parent:WaitForChild("FishingLine"))
local FisherPoses = require(script.Parent:WaitForChild("FisherPoses"))

local FOLDER_NAME = "FishingFx"
local RAINBOW_TAG = "RainbowFish"
local RAINBOW_RATE = 20 -- перекрасок в секунду
local RAINBOW_HELD_RATE = 5 -- … рыбы в руках персонажа (её Color пересобирает меш персонажа)
local RAINBOW_STEPS = 12 -- … ступеней тона на круг (ступень не сменилась — не пишем)
local RING_POOL = 8 -- столько погасших «оснасток» кругов рыбак держит про запас
local FAR_PIVOT = 0.25 -- далёкий поплавок (дальше Fx.Range) переставляется не чаще, с
local RETRACT_TIME = 0.45 -- поплавок сматывается к удочке, с
local DEFAULT_FLOAT_DEPTH = 0.6
local FALLBACK_FISH = "Crucian" -- рыба ушла до подсечки (вид неизвестен) — уплывает карасик
local PILLAR_CORE = 1.2 -- толщина белой сердцевины столба света, studs
local FEET = 3 -- от центра HumanoidRootPart до земли под ногами (если луч вниз ничего не нашёл), studs
local BOBBER_SCALE = 1.7 -- копия поплавка крупнее шаблона во столько раз
local OWN_BOBBER_SCALE = 2.2 -- … а свой — во столько (≈13×16 px на телефоне)
local OWN_SOUND_DISTANCE = 60 -- свои звуки (поплавок, прыжок) громкие до этого расстояния, studs
local CAMERA_IN = 0.35 -- камера сдвигается, с
local CAMERA_OUT = 0.5 -- … и возвращается, с
local CAMERA_POLL = 0.25 -- как часто проверять, не пора ли вернуть камеру (рыба над головой ушла), с
local NIBBLE_DIP = 0.5 -- «примерка»: поплавок притапливается на столько studs …
local NIBBLE_TIME = 0.3 -- … и всплывает обратно за столько секунд
local NIBBLE_MARK = 0.45 -- «?» над поплавком на «примерке», с
local POP_HEIGHT = 2.5 -- рыба сорвалась: поплавок подскакивает на столько studs …
local POP_TIME = 0.4 -- … и шлёпается обратно за столько секунд (потом сматывается)
local SPOUT_RISE = 0.18 -- столб воды поднимается, с
local SPOUT_FADE = 0.4 -- … и тает, с
-- Приземление рыбы над головой — короткий чёткий удар В ТОЧКЕ рыбы, не заливка кадра: маленький
-- белый шар (вспыхивает и гаснет за POP_GROW + POP_FADE), тонкое кольцо-ореол и «звезда» лучей
-- (FX.Burst*: тонкие лучи цвета редкости выстреливают из-за рыбы и гаснут); свой столб света —
-- через FX.OwnPillarDelay, когда удар уже прошёл, и с тонкой сердцевиной (FX.OwnPillarCore).
local HALO_FROM, HALO_TO, HALO_TIME = 1.5, 5.2, 0.38 -- ореол над рыбой: диаметр, studs; время, с
local POP_SIZE, POP_GROW, POP_FADE = 2.4, 0.06, 0.16 -- вспышка-шар над рыбой: studs; с; с
-- Табличка над рыбой: studs + пиксели (как «!» поклёвки) — вблизи около 9 × 3 studs, а с
-- соседнего пирса (≈240 studs) всё ещё читается (≈160 × 52 px); буквы — Montserrat Heavy
-- (UIConfig.Font, шрифт интерфейса «Симулятор») с тёмной круглой обводкой, без плашки — как
-- надписи над миром у образца («МАГАЗИН СЛЕДОВ», «БЕСПЛАТНО!»).
local NAMEPLATE_STUDS, NAMEPLATE_PIXELS = Vector2.new(4, 1.25), Vector2.new(150, 48)
local PLATE_FONT = Font.new(UIConfig.Font.Family, Enum.FontWeight.Heavy)
local TROPHY_PILLAR_TIME = 1.2 -- свой трофей «вспыхивает» после карточки: короткий столб света, с
-- Прыжок пойманной рыбы: из воды она уже крупнее настоящей — на такую долю пути к размеру над
-- головой (FishingConfig.HeldScale), и дорастает до него к такой доле прыжка.
local LEAP_START, LEAP_GROWN = 0.4, 0.8
-- … на невысоком экране (телефон: ниже стольких px) — без столба и с меньшим ореолом (HALO_TO ×
-- TROPHY_SHORT_HALO): столб над рыбой вставал бы за счётчиком улова, ореол — его окружал.
local TROPHY_SHORT_SCREEN, TROPHY_SHORT_HALO = 500, 0.7
local PLATE_AFTER_CARD = 0.5 -- своя табличка: «повтора» трофея не было — выскакивает через столько после карточки, с
local PLATE_OUT = 0.14 -- рыбу убрали: табличка «выдыхает» и тает за столько, с (не висит без неё)
-- Своя табличка у кнопок HUD (fitOwnPlate): не мельче minScale; sway — на сколько studs она ходит в
-- каждую сторону по X и Y (FishLife: покачивание и подскок за рыбой; рыбак празднует — приседает,
-- прыгает, качает рыбу: вбок — на доли stud, вверх-вниз — почти на stud).
local PLATE_FIT = { minScale = 0.7, sway = Vector2.new(0.2, 0.8) }
local ALERT_OTHER_DISTANCE = 90 -- чужой «!» виден не дальше, studs
local OWN_PILLAR_WIDTH = 0.4 -- свой столб света уже чужого во столько раз (см. pillar)
local PILLAR_FAR = 80 -- чужой столб дальше стольких studs шире: × расстояние / PILLAR_FAR (≈ 28 px на телефоне)
-- … и выше: не ниже PILLAR_SKY.base + расстояние × PILLAR_SKY.slope studs — с любого пирса луч
-- уходит за верх экрана телефона (камера смотрит на 18° вниз: верх кадра ≈ 0.31 × расстояния).
local PILLAR_SKY = { base = 40, slope = 0.5 }
local PILLAR_FADE_OTHER = 0.55 -- чужой столб начинает гаснуть с этой доли своей жизни (свой — с 0.3)

local Fx = FishingConfig.Fx
local Palette = UIConfig.Palette
local WHITE = Color3.new(1, 1, 1)
local WATER = Palette.Sky.Top -- голубой «водный» цвет брызг и кругов
local SUN_TOP = Palette.Sun.Top
local SUN_BOTTOM = Palette.Sun.Bottom
local INK = UIConfig.Ink
local FONT = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.ExtraBold)

-- Встроенные текстуры и звуки клиента (загружать ничего не нужно; нет файла — тишина).
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SPLASH_TEXTURE = "rbxasset://textures/particles/smoke_main.dds" -- читается как брызги
local SOUND_WHOOSH = "rbxasset://sounds/swoosh.wav"
local SOUND_SPLASH = "rbxasset://sounds/impact_water.mp3"
local SOUND_PING = "rbxasset://sounds/electronicpingshort.wav"

local FX = {
	BobAmplitude = 0.22, -- покачивание на воде, studs
	BobSpeed = 2,
	BiteDip = 1.4, -- насколько ныряет при поклёвке, studs
	BiteSpeed = 9, -- рывков ≈ BiteSpeed / π в секунду (ниже 3 Гц)
	BiteJerk = 0.85, -- рывок «засчитан» (брызги), когда нырок проходит эту долю вниз
	BiteGlowRate = 2.5, -- свой контур мигает жёлтым, Гц
	CastSpins = 2, -- оборотов поплавка в полёте
	ReelSwing = 0.9, -- метания при вытаскивании, studs
	ReelSpeed = 7.5,
	ReelPull = 0.05, -- доля пути к рыбаку за секунду (чужой поплавок)
	ReelPullMax = 0.5,
	-- Свой поплавок подтягивается рывками: каждое попадание в мини-игре ("Zone") — ещё
	-- (ReelPullMax − ReelCreepMax) / HitsNeeded пути за PullTime с (с перелётом), плюс медленно
	-- сам (ReelCreep в секунду, не больше ReelCreepMax) — видно, как идёт борьба.
	ReelCreep = 0.03,
	ReelCreepMax = 0.12,
	PullTime = 0.25,
	LineColor = Color3.fromRGB(245, 245, 235),
	LineTip = 0.06, -- толщина лески у кончика удочки, studs …
	LineFloat = 0.18, -- … и у поплавка (он дальше от камеры)
	LineGlow = 0.25, -- LightEmission лески
	-- (форма лески — провис, натяжение, дрожь, слабина — FishingLine)
	-- Круги чуть выше воды (над её мелкими волнами), волна по земле — чуть выше самого высокого
	-- из лучей вниз; толщина колец — от 0,4 stud: вода видна с пирса под острым углом.
	RingLift = 0.3,
	GroundLift = 0.25,
	GroundProbe = 2.5, -- лучи вниз: под ногами и в 4 точках на таком расстоянии, studs
	GroundBump = 0.75, -- … выше ног больше чем на столько — не земля (перила, ящик), studs
	-- «!» над поплавком: studs + пиксели (не теряется вдали и на телефоне). Гуи сразу
	-- максимального размера (AlertRoom), прыгает и пульсирует UIScale внутри (без пересчёта
	-- TextScaled каждый кадр).
	AlertLift = 3.4, -- свой «!» крупный: выше, чтобы не закрывал нырок поплавка
	AlertOtherLift = 2.4,
	AlertStuds = 1,
	AlertPixels = 40,
	AlertOtherStuds = 1.4,
	AlertOtherPixels = 12,
	AlertRoom = 1.45,
	AlertText = 34,
	AlertOtherText = 18,
	AlertStarText = 14,
	AlertStars = 5,
	-- Сдвиг камеры своего рыбака (Humanoid.CameraOffset): вправо и вверх; пока своя рыба над
	-- головой, а карточка улова уже открылась (она прячет сдвиг), — ещё чуть выше (TrophyCamera):
	-- рыба и табличка опускаются на ≈13 px и не задевают счётчик улова после карточки.
	CameraOffset = Vector3.new(2.2, 1, 0),
	TrophyCamera = Vector3.new(2.2, 1.6, 0),
	-- … и ещё выше на такую долю того, на сколько рыба над головой выросла вверх (атрибут Scale
	-- у HeldFish: она растёт от макушки вверх) — крупная рыба и её табличка остаются в кадре.
	TrophyLift = 0.5,
	-- v3: удар приземления — «звезда» тонких лучей: сколько, за сколько секунд, во сколько раз
	-- шире рыбы; свой столб света — позже удара и тоньше.
	BurstRays = 10,
	BurstTime = 0.28,
	BurstReach = 2.1,
	OwnPillarDelay = 0.3,
	OwnPillarCore = 0.5,
	-- Поплавок приводнился: «плюх» — нырнул на Plop studs, вынырнул с перелётом и закачался
	-- (пружина PlopHz, затухание PlopDamp), накренившись по полёту на PlopTilt рад; PlopTime с.
	Plop = 0.55,
	PlopHz = 2.2,
	PlopDamp = 5,
	PlopTilt = 0.3,
	PlopTime = 0.8,
	WhipAfter = 0.18, -- след кончика удочки гаснет через столько после срыва поплавка, с
	-- Рыба над головой живёт (FishLife): ближе LifeNear studs — гнётся, до LifeRange — качается
	-- целиком (через кадр), дальше — в покое (проверка раз в LifePoll с, таймером).
	LifeNear = 60,
	LifeRange = 120,
	LifePoll = 0.5,
	-- Тень рыбы (FishShadow) крупнее у редкой рыбы: своя — по редкости из мини-игры, чужая — ShadowOther.
	ShadowScale = { Common = 1, Rare = 1.15, Epic = 1.35, Legendary = 1.6, Mythic = 1.9 } :: { [string]: number },
	ShadowOther = 1.2,
}

-- Сколько капель в каждом всплеске (размер капель один на все — меняется только скорость).
local SPLASH = {
	landing = 24,
	bite = 36,
	jerk = 10,
	reel = 8,
	catch = 45,
	lost = 28,
	pop = 12,
	nibble = 10,
}

type RingLook = {
	from: number, -- диаметр в начале, studs
	to: number, -- диаметр в конце
	time: number, -- с
	color: Color3, -- внешнее кольцо
	inner: Color3, -- внутреннее, тоньше
	width: number, -- толщина внешнего кольца в начале, studs
	foam: boolean?, -- белый «пятак» пены в середине первого кольца
}

local RING: { [string]: RingLook } = {
	ripple = { from = 1.2, to = 6.5, time = 1.5, color = WHITE, inner = WATER, width = 0.38 },
	landing = { from = 1.4, to = 8, time = 1.1, color = WHITE, inner = WATER, width = 0.5, foam = true },
	bite = { from = 1.6, to = 10, time = 0.95, color = WHITE, inner = SUN_TOP, width = 0.6, foam = true },
	jerk = { from = 1.2, to = 4, time = 0.8, color = WHITE, inner = SUN_TOP, width = 0.42 },
	reel = { from = 1.2, to = 5.5, time = 0.8, color = WHITE, inner = WATER, width = 0.42 },
	lost = { from = 1.4, to = 7.5, time = 1, color = WHITE, inner = WATER, width = 0.5, foam = true },
	nibble = { from = 1, to = 5, time = 0.8, color = WHITE, inner = WATER, width = 0.4 },
}

type Alert = {
	gui: BillboardGui,
	lift: number, -- StudsOffset.Y без прыжков
	scale: UIScale, -- Holder.FxScale: выскакивание и пульс
	glow: Frame,
	badge: Frame,
	label: TextLabel,
	stars: { TextLabel }, -- только у своего «!»
}

type Bobber = {
	player: Player,
	own: boolean, -- поплавок этого клиента
	trove: Trove.Trove,
	model: Model,
	root: BasePart,
	lineAttachment: Attachment,
	line: FishingLine.Line, -- леска (форма, вспышки — FishingLine)
	beam: Beam, -- = line.beam
	splash: ParticleEmitter,
	trails: { Trail },
	wake: Trail,
	glow: Highlight?, -- контур своего поплавка
	whoosh: Sound,
	splashSound: Sound,
	pingSound: Sound,
	alert: Alert,
	floatDepth: number, -- от pivot копии вниз до ватерлинии
	state: string, -- FishingState игрока ("Waiting" | "Bite" | "Reeling")
	stateSince: number, -- os.clock() смены состояния
	target: Vector3, -- где pivot поплавка на воде (BobberTarget + FloatDepth)
	castTime: number, -- CastTime: поплавок срывается с кончика (до этого — висит на нём, замах)
	launchAt: number, -- … на этом клиенте (заброс увиден поздно — не раньше, чем через
	-- Fx.LaunchGuard после того; приводняется всё равно в CastTime + CastFlightTime)
	launched: boolean, -- свист и след уже включены (в миг срыва)
	position: Vector3, -- где поплавок сейчас
	landed: boolean,
	landedAt: number, -- os.clock() приводнения («плюх»)
	fresh: boolean, -- создан, пока летел (заброс видели — приводнение с брызгами)
	nextSplash: number,
	nextRipple: number,
	dip: number, -- нырок поклёвки в прошлом кадре, 0..1 (для рывков)
	jerks: number, -- сколько рывков за эту поклёвку
	nibbleAt: number?, -- os.clock() начала «примерки»
	popStart: number?, -- os.clock(): рыба сорвалась, поплавок подскакивает
	popSplashed: boolean,
	retractFrom: Vector3?, -- сматывается отсюда (после "Idle")
	retractStart: number,
	hooked: Effect?, -- на крючке рыба в прыжке: поплавок летит вместе с ней
	tip: Attachment?,
	nextTipSearch: number,
	seed: number, -- своя фаза покачивания
	whipped: boolean, -- след кончика этого заброса уже был
	rarity: string?, -- своя рыба: редкость из мини-игры (тень крупнее у редкой)
	hitsNeeded: number?, -- своя мини-игра: сколько попаданий нужно ("Minigame") …
	hits: number, -- … сколько уже ("Zone")
	hitAt: number, -- os.clock() последнего попадания
	pullFrom: number, -- где был поплавок (доля пути) в миг попадания
	hangFade: number, -- свой поплавок на кончике удочки при замахе у самой камеры — прозрачнее
	shadow: FishShadow.Shadow?, -- тень рыбы под водой (своя и вблизи)
	shadowGone: string?, -- тень уходит: "caught" | "lost" | "gone"
	pivotAt: number, -- os.clock() последней перестановки (далёкий — раз в FAR_PIVOT)
	pivotKey: string, -- состояние на ней (сменилось — переставляем сразу)
}

-- Эффект в мире: его детали (instances) удаляются, когда он кончился — сам (по таймеру или
-- step вернул false), вместе с поплавком (owner) или с уходом игрока.
type Effect = {
	tracker: Tracker,
	owner: Bobber?,
	instances: { Instance },
	emitter: ParticleEmitter?, -- считается в Fx.MaxEmitters рыбака
	priority: number, -- нужно место под новый ParticleEmitter — первым уходит меньший
	tag: string?, -- "leap" — прыжок рыбы (камера своего рыбака ждёт его конца)
	thread: thread?,
	step: ((now: number) -> boolean)?, -- покадровый эффект: false — кончился
	onEnd: (() -> ())?,
	done: boolean,
}

type Tracker = {
	player: Player,
	trove: Trove.Trove,
	bobber: Bobber?,
	effects: { [Effect]: true },
	fxEvent: any, -- последнее увиденное значение FishFx
	-- Рыба над головой (FishLife): чья жизнь сейчас идёт (её эффект), ожидание «подойдём ближе».
	life: { held: Model, life: FishLife.Life, effect: Effect }?,
	lifePoll: thread?,
	ringPool: { RingRig }, -- погасшие круги про запас (не больше RING_POOL)
}

-- «Оснастка» круга на воде: невидимая деталь Ripple с SurfaceGui, две рамки-кольца и белый
-- «пятак» пены; tweens — анимации её текущего круга (гасятся, когда круг вернулся в пул).
type RingRig = {
	part: Part,
	gui: SurfaceGui,
	outer: Frame,
	outerStroke: UIStroke,
	inner: Frame,
	innerStroke: UIStroke,
	foam: Frame,
	tweens: { Tween },
}

type FxEvent = { kind: string, id: string?, mutation: string?, rarity: string }

type RainbowModel = { parts: { BasePart }, u: { number }, v: { number }, step: number?, nextPaint: number }

local FishingFxController = {
	-- (rarity: string, worldPosition: Vector3) — своя рыба долетела (см. шапку).
	OwnFishLanded = Signal.new(),
	-- (player: Player, basePosition: Vector3, rarity: string) — у другого рыбака встал столб
	-- света легендарной / мифической рыбы (см. шапку).
	OtherTrophy = Signal.new(),
	-- () — свой трофей «вспыхнул» ещё раз (ReplayOwnTrophy вернул true).
	TrophyReplayed = Signal.new(),
}

local folder: Folder? = nil
local bobbersFolder: Instance? = nil
local fishFolder: Instance? = nil
local trackers: { [Player]: Tracker } = {}
local active: { [Bobber]: true } = {}
local frameEffects: { [Effect]: true } = {}
local frameConnection: RBXScriptConnection? = nil
local rainbow: { [Instance]: RainbowModel } = {}
local rainbowConnection: RBXScriptConnection? = nil
local rigOf: { [Instance]: RingRig } = {} -- деталь круга -> её оснастка (возвращается в пул)
local playerGui: PlayerGui? = nil
local hudGui: ScreenGui? = nil -- свой HUD (атрибут CounterHold — улов на экране)
local rng = Random.new()

--------------------------------------------------------------------------------
-- Помощники
--------------------------------------------------------------------------------

local function finite(value: any): number?
	if typeof(value) == "number" and value == value and math.abs(value) ~= math.huge then
		return value
	end
	return nil
end

-- Отменяет ожидающий поток (кроме того, что выполняется сейчас).
local function cancelThread(thread: thread?)
	if thread and thread ~= coroutine.running() and coroutine.status(thread) == "suspended" then
		task.cancel(thread)
	end
end

-- Всплеск частиц. pcall: в эмуляторе тестов (RbxSim) у ParticleEmitter нет метода Emit.
local function burst(emitter: ParticleEmitter, count: number)
	pcall(function()
		emitter:Emit(count)
	end)
end

local function tween(instance: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local playing = TweenService:Create(instance, info, goal)
	playing:Play()
	return playing
end

-- { {время, значение, разброс?} } → NumberSequence.
local function numbers(points: { { number } }): NumberSequence
	local keys = {}
	for _, point in points do
		table.insert(keys, NumberSequenceKeypoint.new(point[1], point[2], point[3] or 0))
	end
	return NumberSequence.new(keys)
end

-- Плавный градиент по списку цветов.
local function gradient(colors: { Color3 }): ColorSequence
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local keys = {}
	for index, color in colors do
		table.insert(keys, ColorSequenceKeypoint.new((index - 1) / (#colors - 1), color))
	end
	return ColorSequence.new(keys)
end

-- Цвет полосами (конфетти): частицы с разным временем жизни в один момент разного цвета.
local function stripes(colors: { Color3 }): ColorSequence
	local count = math.min(#colors, 10) -- в ColorSequence не больше 20 точек
	local keys = {}
	for index = 1, count do
		local color = colors[index]
		table.insert(keys, ColorSequenceKeypoint.new((index - 1) / count, color))
		table.insert(keys, ColorSequenceKeypoint.new(if index == count then 1 else index / count - 0.001, color))
	end
	return ColorSequence.new(keys)
end

-- Цвета следа, искр и колец рыбы этой редкости (обычная — белый с голубым, мифическая — радуга).
local function rarityColors(rarity: string): { Color3 }
	local style = UIConfig.Rarity[rarity]
	if not style or rarity == "Common" then
		return { WHITE, WATER }
	elseif style.Rainbow then
		return UIConfig.Rainbow
	end
	return { WHITE, style.Top, style.Bottom }
end

-- Заглавные буквы, включая кириллицу (string.upper меняет только латиницу).
local function upper(text: string): string
	local out = {}
	for _, code in utf8.codes(text) do
		if (code >= 0x430 and code <= 0x44F) or (code >= 0x61 and code <= 0x7A) then
			code -= 0x20
		elseif code == 0x451 then
			code = 0x401
		end
		table.insert(out, utf8.char(code))
	end
	return table.concat(out)
end

-- Деталь эффекта: закреплена, без столкновений, запросов и теней.
local function quietPart(name: string, size: Vector3, cframe: CFrame): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic -- без LEGO-шипов (их рисует только Plastic)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = size
	part.CFrame = cframe
	return part
end

-- Невидимая деталь-держатель для лучей (Beam) с двумя точками: Bottom и Top.
local function beamHost(name: string, position: Vector3): (Part, Attachment, Attachment)
	local host = quietPart(name, Vector3.new(0.2, 0.2, 0.2), CFrame.new(position))
	host.Transparency = 1
	local bottom = Instance.new("Attachment")
	bottom.Name = "Bottom"
	bottom.Parent = host
	local top = Instance.new("Attachment")
	top.Name = "Top"
	top.Position = Vector3.new(0, 0.1, 0)
	top.Parent = host
	return host, bottom, top
end

local function makeBeam(name: string, host: Instance, a0: Attachment, a1: Attachment): Beam
	local beam = Instance.new("Beam")
	beam.Name = name
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.FaceCamera = true
	beam.Segments = 1
	beam.LightInfluence = 0
	beam.Parent = host
	return beam
end

-- Звук; own — свой (поплавок и прыжок своей рыбы): громкий и в 60 studs от камеры за спиной.
local function makeSound(parent: Instance, name: string, id: string, volume: number, own: boolean?): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.Volume = volume
	sound.RollOffMinDistance = if own then OWN_SOUND_DISTANCE else 10
	sound.RollOffMaxDistance = if own then 200 else 140
	sound.Parent = parent
	return sound
end

local function play(sound: Sound, speed: number?)
	sound.PlaybackSpeed = speed or rng:NextNumber(0.92, 1.1)
	pcall(function()
		sound:Play()
	end)
end

-- Где смотрит этот игрок: его персонаж (без персонажа — камера).
local function viewerPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local camera = Workspace.CurrentCamera
	return if camera then camera.CFrame.Position else nil
end

-- Видно ли отсюда эффект в точке position (дальше Fx.Range — не рисуем).
local function isNear(position: Vector3): boolean
	local viewer = viewerPosition()
	return viewer == nil or (viewer - position).Magnitude <= Fx.Range
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Где голова своего персонажа (для OwnFishLanded без прыжка): над головой, иначе камера.
local function ownHeadPoint(): Vector3
	local character = Players.LocalPlayer.Character
	local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	if head and head:IsA("BasePart") then
		return head.Position + Vector3.new(0, 2, 0)
	end
	local camera = Workspace.CurrentCamera
	return if camera then camera.Focus.Position else Vector3.zero
end

--------------------------------------------------------------------------------
-- Эффекты: учёт, покадровый цикл, лимит ParticleEmitter'ов
--------------------------------------------------------------------------------

-- Погасший круг: анимации стоп, деталь из мира, оснастка — в пул рыбака (пул полон или рыбака
-- уже нет — удаляется).
local function releaseRig(tracker: Tracker, rig: RingRig)
	for _, t in rig.tweens do
		t:Cancel()
	end
	table.clear(rig.tweens)
	rig.part.Parent = nil
	if trackers[tracker.player] == tracker and #tracker.ringPool < RING_POOL then
		table.insert(tracker.ringPool, rig)
	else
		rigOf[rig.part] = nil
		rig.part:Destroy()
	end
end

local function endEffect(effect: Effect)
	if effect.done then
		return
	end
	effect.done = true
	effect.tracker.effects[effect] = nil
	frameEffects[effect] = nil
	cancelThread(effect.thread)
	effect.thread = nil
	local onEnd = effect.onEnd
	effect.onEnd = nil
	if onEnd then
		onEnd()
	end
	for _, instance in effect.instances do
		local rig = rigOf[instance]
		if rig then
			releaseRig(effect.tracker, rig)
		else
			instance:Destroy()
		end
	end
	table.clear(effect.instances)
	effect.emitter = nil
end

-- Новый эффект рыбака; life — через сколько секунд он кончится сам (nil — решит step).
local function newEffect(tracker: Tracker, life: number?, owner: Bobber?): Effect
	local effect: Effect = {
		tracker = tracker,
		owner = owner,
		instances = {},
		emitter = nil,
		priority = 0,
		tag = nil,
		thread = nil,
		step = nil,
		onEnd = nil,
		done = false,
	}
	tracker.effects[effect] = true
	if life then
		effect.thread = task.delay(life, function()
			effect.thread = nil
			endEffect(effect)
		end)
	end
	return effect
end

local stepBobber: (bobber: Bobber, now: number) -> ()

local function onFrame()
	local now = os.clock()
	for bobber in active do
		stepBobber(bobber, now)
	end
	-- Копия: шаг может закончить эффект или начать новый.
	for effect in table.clone(frameEffects) do
		local step = effect.step
		if not effect.done and step then
			local ok, alive = pcall(step, now)
			if not ok then
				warn("[FishingFxController] эффект упал:", alive)
			end
			if not ok or not alive then
				endEffect(effect)
			end
		end
	end
	if next(active) == nil and next(frameEffects) == nil and frameConnection then
		frameConnection:Disconnect()
		frameConnection = nil
	end
end

local function ensureFrame()
	if not frameConnection then
		frameConnection = RunService.RenderStepped:Connect(onFrame)
	end
end

-- Эффект, который обновляется каждый кадр, пока step возвращает true.
local function runEveryFrame(effect: Effect, step: (now: number) -> boolean)
	effect.step = step
	frameEffects[effect] = true
	ensureFrame()
end

-- Сколько ParticleEmitter'ов рыбака сейчас в мире (у поплавка — один, «Splash»).
local function emitterCount(tracker: Tracker): number
	local count = if tracker.bobber then 1 else 0
	for effect in tracker.effects do
		if effect.emitter then
			count += 1
		end
	end
	return count
end

-- Освобождает место под extra новых ParticleEmitter'ов (не больше Fx.MaxEmitters на рыбака):
-- кончаются эффекты с меньшим priority (искры над рыбой, потом конфетти).
local function makeRoom(tracker: Tracker, extra: number)
	while emitterCount(tracker) + extra > Fx.MaxEmitters do
		local weakest: Effect? = nil
		for effect in tracker.effects do
			if effect.emitter and (weakest == nil or effect.priority < weakest.priority) then
				weakest = effect
			end
		end
		if not weakest then
			return
		end
		endEffect(weakest)
	end
end

--------------------------------------------------------------------------------
-- Камера своего рыбака (Humanoid.CameraOffset, см. шапку)
--------------------------------------------------------------------------------

local cameraHumanoid: Humanoid? = nil -- чей CameraOffset сейчас сдвинут (nil — ничей)
local cameraThread: thread? = nil -- следующая проверка, пока сдвинут
-- Куда сдвинут; trophy — своя рыба над головой и карточка улова уже открывалась (FX.TrophyCamera).
local cameraState: { offset: Vector3?, trophy: boolean } = { offset = nil, trophy = false }

-- Своя рыбалка ещё на экране: леска в воде, поплавок сматывается, рыба в прыжке или над головой.
local function ownFishingShown(): boolean
	local player = Players.LocalPlayer
	local state = player:GetAttribute("FishingState")
	if state == "Waiting" or state == "Bite" or state == "Reeling" then
		return true
	end
	local tracker = trackers[player]
	if tracker then
		if tracker.bobber then
			return true
		end
		for effect in tracker.effects do
			if effect.tag == "leap" then
				return true
			end
		end
	end
	local character = player.Character
	return character ~= nil and character:FindFirstChild("HeldFish") ~= nil
end

local function tweenCameraOffset(humanoid: Humanoid, offset: Vector3, time: number)
	local direction = if offset == Vector3.zero then Enum.EasingDirection.InOut else Enum.EasingDirection.Out
	tween(humanoid, TweenInfo.new(time, Enum.EasingStyle.Quad, direction), { CameraOffset = offset })
end

local updateCamera: () -> ()

local function pollCamera()
	cameraThread = nil
	updateCamera()
end

-- Сдвигает камеру, когда своя рыбалка началась, и возвращает, когда она совсем кончилась
-- (рыба над головой исчезла — это заметит проверка раз в CAMERA_POLL секунд).
updateCamera = function()
	local wanted = ownFishingShown()
	local character = Players.LocalPlayer.Character
	local humanoid: Humanoid? = nil
	if wanted then
		humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	end
	-- Своя рыба над головой: как только открылась карточка улова (она закрывает сдвиг) — выше.
	if not (character and character:FindFirstChild("HeldFish")) then
		cameraState.trophy = false
	elseif not cameraState.trophy then
		local fishing = hudGui and hudGui:FindFirstChild("Fishing")
		local card = fishing and fishing:FindFirstChild("CatchCard")
		cameraState.trophy = card ~= nil and card:IsA("GuiObject") and card.Visible
	end
	local offset = FX.CameraOffset
	if cameraState.trophy then
		local held = character and character:FindFirstChild("HeldFish")
		local scale = held and held:GetAttribute("Scale")
		local extra = 0
		if held and held:IsA("Model") and typeof(scale) == "number" and scale > 1 then
			local _, box = held:GetBoundingBox()
			extra = FX.TrophyLift * box.Y * (1 - 1 / scale)
		end
		offset = FX.TrophyCamera + Vector3.new(0, extra, 0)
	end
	if humanoid ~= cameraHumanoid then
		local old = cameraHumanoid
		cameraHumanoid = humanoid
		if old and old:IsDescendantOf(Workspace) then
			tweenCameraOffset(old, Vector3.zero, CAMERA_OUT)
		end
		if humanoid then
			tweenCameraOffset(humanoid, offset, CAMERA_IN)
		end
		cameraState.offset = if humanoid then offset else nil
	elseif humanoid and cameraState.offset ~= offset then
		cameraState.offset = offset
		tweenCameraOffset(humanoid, offset, CAMERA_IN)
	end
	if wanted and cameraThread == nil then
		cameraThread = task.delay(CAMERA_POLL, pollCamera)
	end
end

local function isOwn(tracker: Tracker): boolean
	return tracker.player == Players.LocalPlayer
end

--------------------------------------------------------------------------------
-- Круги на воде (плоская невидимая деталь + SurfaceGui с кольцами из UIStroke)
--------------------------------------------------------------------------------

local function roundFrame(parent: Instance, name: string, scale: number, color: Color3, transparency: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(scale, scale)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	frame.Parent = parent
	return frame
end

local function ringStroke(frame: Frame, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	return stroke
end

-- Новая оснастка круга (берётся, когда пул рыбака пуст).
local function newRig(): RingRig
	local part = quietPart("Ripple", Vector3.new(1, 0.05, 1), CFrame.identity)
	part.Transparency = 1
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Ring"
	gui.Face = Enum.NormalId.Top
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.MaxDistance = Fx.Range
	gui.Parent = part
	local outer = roundFrame(gui, "Outer", 1, WHITE, 1)
	local inner = roundFrame(gui, "Inner", 1, WHITE, 1)
	local foam = roundFrame(gui, "Foam", 1, WHITE, 0.45)
	local rig: RingRig = {
		part = part,
		gui = gui,
		outer = outer,
		outerStroke = ringStroke(outer, WHITE, 1),
		inner = inner,
		innerStroke = ringStroke(inner, WHITE, 1),
		foam = foam,
		tweens = {},
	}
	rigOf[part] = rig
	return rig
end

local function rigTween(rig: RingRig, instance: Instance, info: TweenInfo, goal: { [string]: any })
	table.insert(rig.tweens, tween(instance, info, goal))
end

-- Одно расходящееся кольцо (внешнее белое + внутреннее цветное), гаснет за look.time.
-- Деталь и холст SurfaceGui сразу конечного размера (≤ 256 пикселей), растут только рамки
-- внутри: холст не пересоздаётся каждый кадр. Оснастка — из пула рыбака (endEffect вернёт её).
local function spawnRing(effect: Effect, position: Vector3, look: RingLook, foam: boolean)
	local parent = folder
	if not parent then
		return
	end
	local size = look.to
	local pixels = math.clamp(256 / size, 8, 24)
	local start = math.clamp(look.from / size, 0.05, 1)
	local rig = table.remove(effect.tracker.ringPool) or newRig()
	rig.part.Size = Vector3.new(size, 0.05, size)
	rig.part.CFrame = CFrame.new(position)
	rig.gui.PixelsPerStud = pixels
	rig.outer.Size = UDim2.fromScale(0.92 * start, 0.92 * start)
	rig.outer.BackgroundColor3 = look.color
	rig.outerStroke.Color = look.color
	rig.outerStroke.Thickness = look.width * pixels
	rig.outerStroke.Transparency = 0
	rig.inner.Size = UDim2.fromScale(0.8 * start, 0.8 * start)
	rig.inner.BackgroundColor3 = look.inner
	rig.innerStroke.Color = look.inner
	rig.innerStroke.Thickness = look.width * 0.6 * pixels
	rig.innerStroke.Transparency = 0
	rig.foam.Visible = foam
	rig.foam.Size = UDim2.fromScale(0.7 * start, 0.7 * start)
	rig.foam.BackgroundTransparency = 0.45
	rig.part.Parent = parent
	table.insert(effect.instances, rig.part)

	local grow = TweenInfo.new(look.time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fade = TweenInfo.new(look.time, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
	rigTween(rig, rig.outer, grow, { Size = UDim2.fromScale(0.92, 0.92) })
	rigTween(rig, rig.inner, grow, { Size = UDim2.fromScale(0.8, 0.8) })
	rigTween(rig, rig.outerStroke, fade, { Transparency = 1, Thickness = rig.outerStroke.Thickness * 0.4 })
	rigTween(rig, rig.innerStroke, fade, { Transparency = 1, Thickness = rig.innerStroke.Thickness * 0.4 })
	if foam then
		local foamTo = 0.5 * (start + 0.7 * (1 - start))
		rigTween(
			rig,
			rig.foam,
			TweenInfo.new(look.time * 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1, Size = UDim2.fromScale(foamTo, foamTo) }
		)
	end
end

-- Сколько кругов рыбака сейчас на воде и на земле.
local function liveRings(tracker: Tracker): number
	local count = 0
	for effect in tracker.effects do
		for _, instance in effect.instances do
			if instance.Name == "Ripple" then
				count += 1
			end
		end
	end
	return count
end

-- Столб воды там, где рыба выходит из воды или ныряет: луч (Beam) лицом к камере растёт на
-- height studs за SPOUT_RISE и тает за SPOUT_FADE. Без частиц — виден и издалека.
local function spout(tracker: Tracker, water: Vector3, height: number)
	local parent = folder
	if not parent then
		return
	end
	local host, bottom, top = beamHost("Spout", water)
	local beam = makeBeam("Water", host, bottom, top)
	beam.Width0 = 2.4
	beam.Width1 = 0.9
	beam.Texture = SPLASH_TEXTURE
	beam.TextureMode = Enum.TextureMode.Stretch
	beam.TextureLength = 1
	beam.TextureSpeed = 1.5
	beam.Color = ColorSequence.new(WHITE, WATER)
	beam.LightEmission = 0.5
	beam.Transparency = NumberSequence.new(0.1)
	host.Parent = parent
	local effect = newEffect(tracker, nil)
	table.insert(effect.instances, host)
	local start = os.clock()
	runEveryFrame(effect, function(now: number): boolean
		local age = now - start
		if age >= SPOUT_RISE + SPOUT_FADE then
			return false
		end
		local rise = math.min(age / SPOUT_RISE, 1)
		top.Position = Vector3.new(0, math.max(height * (1 - (1 - rise) ^ 2), 0.1), 0)
		local fade = math.clamp((age - SPOUT_RISE) / SPOUT_FADE, 0, 1)
		beam.Transparency = numbers({ { 0, 0.1 + 0.9 * fade }, { 1, 0.35 + 0.65 * fade } })
		return true
	end)
end

-- Пачка из count колец с паузой gap (каждое следующее чуть меньше), начиная через delay
-- секунд; owner — поплавок, с которым кольца исчезают.
local function ringBurst(
	tracker: Tracker,
	owner: Bobber?,
	position: Vector3,
	look: RingLook,
	count: number,
	gap: number,
	delay: number?
)
	local effect = newEffect(tracker, nil, owner)
	effect.thread = task.spawn(function()
		if delay then
			task.wait(delay)
		end
		for index = 1, count do
			local shrink = 1 - 0.14 * (index - 1)
			local ring = table.clone(look)
			ring.to = look.to * shrink
			spawnRing(effect, position, ring, look.foam == true and index == 1)
			if index < count then
				task.wait(gap)
			end
		end
		task.wait(look.time)
		effect.thread = nil
		endEffect(effect)
	end)
end

-- Круги поплавка быстро гаснут (леску сматывают).
local function fadeOwned(tracker: Tracker, bobber: Bobber)
	local info = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for effect in tracker.effects do
		if effect.owner == bobber then
			for _, instance in effect.instances do
				local rig = rigOf[instance]
				for _, item in instance:GetDescendants() do
					local goal = if item:IsA("UIStroke")
						then { Transparency = 1 }
						elseif item:IsA("Frame") then { BackgroundTransparency = 1 }
						else nil
					if goal and rig then
						rigTween(rig, item, info, goal)
					elseif goal then
						tween(item, info, goal)
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Кончик удочки и цель заброса
--------------------------------------------------------------------------------

-- Кончик удочки в руке персонажа (Tool с атрибутом RodId: сначала та, что в RodId игрока).
local function findTip(player: Player): Attachment?
	local character = player.Character
	if not character then
		return nil
	end
	local wanted = player:GetAttribute("RodId")
	local found: Attachment? = nil
	for _, item in character:GetChildren() do
		local rodId = item:GetAttribute("RodId")
		if item:IsA("Tool") and typeof(rodId) == "string" then
			local handle = item:FindFirstChild("Handle")
			local tip = handle and handle:FindFirstChild("TipAttachment")
			if tip and tip:IsA("Attachment") then
				found = tip
				if rodId == wanted then
					break
				end
			end
		end
	end
	return found
end

-- Кончик удочки, найденный заново, если удочку убрали/сменили (не чаще 4 раз в секунду).
local function resolveTip(bobber: Bobber, now: number): Attachment?
	local tip = bobber.tip
	local character = bobber.player.Character
	if tip and character and tip:IsDescendantOf(character) then
		return tip
	end
	if now >= bobber.nextTipSearch then
		bobber.nextTipSearch = now + 0.25
		tip = findTip(bobber.player)
		bobber.tip = tip
		-- Без кончика леска просто выключается (Enabled = tip ~= nil в stepBobber); старую
		-- Attachment0 не стираем.
		if tip then
			bobber.beam.Attachment0 = tip
		end
	end
	return bobber.tip
end

-- Откуда летит / куда сматывается поплавок: кончик удочки, без удочки — над головой.
local function anchorPosition(bobber: Bobber, tip: Attachment?): Vector3
	if tip then
		return tip.WorldPosition
	end
	local character = bobber.player.Character
	local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	if head and head:IsA("BasePart") then
		return head.Position + Vector3.new(0, 1.5, 0)
	end
	return bobber.position
end

-- Куда упадёт поплавок, если сервер не прислал BobberTarget: прямо перед рыбаком на воде.
local function fallbackTarget(player: Player): Vector3
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return Vector3.new(0, MapConfig.WaterTop, 0)
	end
	local rodId = player:GetAttribute("RodId")
	local distance = RodConfig.Rods[1].CastDistance
	for _, rod in RodConfig.Rods do
		if rod.Id == rodId then
			distance = rod.CastDistance
		end
	end
	local ahead = root.Position + root.CFrame.LookVector * distance
	return Vector3.new(ahead.X, MapConfig.WaterTop, ahead.Z)
end

-- Цель заброса (pivot поплавка на воде: ватерлиния как раз на воде) и время заброса.
local function readCast(bobber: Bobber)
	local player = bobber.player
	local target = player:GetAttribute("BobberTarget")
	local water = if typeof(target) == "Vector3" then target else fallbackTarget(player)
	bobber.target = water + Vector3.new(0, bobber.floatDepth, 0)
	local now = Workspace:GetServerTimeNow()
	local castTime = finite(player:GetAttribute("CastTime")) or now
	if castTime ~= bobber.castTime then
		bobber.castTime = castTime
		-- Увидели заброс позже, чем за Fx.LaunchGuard до срыва (сеть медленнее CastWindUp):
		-- срыв чуть позже, полёт короче — приводнение в то же время (FisherAnimController так же).
		bobber.launchAt = math.min(math.max(castTime, now + Fx.LaunchGuard), castTime + FishingConfig.CastFlightTime)
		bobber.launched = false
	end
end

-- Точка на воде под поплавком (центр кругов и всплесков).
local function waterUnder(bobber: Bobber, position: Vector3?): Vector3
	local at = position or bobber.position
	return Vector3.new(at.X, bobber.target.Y - bobber.floatDepth, at.Z)
end

--------------------------------------------------------------------------------
-- Создание поплавка
--------------------------------------------------------------------------------

-- Брызги: один вид капель на все всплески (размер не меняется на лету — капли, уже летящие,
-- не съёживаются), меняются только скорость и число.
local function makeSplash(root: BasePart): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Splash"
	emitter.Enabled = false
	emitter.Rate = 0
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(9, 16)
	emitter.SpreadAngle = Vector2.new(55, 55)
	emitter.Acceleration = Vector3.new(0, -55, 0)
	emitter.Drag = 0.4
	emitter.Orientation = Enum.ParticleOrientation.VelocityParallel
	emitter.Size = numbers({ { 0, 1, 0.45 }, { 0.25, 1.35, 0.45 }, { 1, 0.25 } })
	emitter.Squash = numbers({ { 0, 1.4 }, { 1, 0.3 } })
	emitter.Transparency = numbers({ { 0, 0 }, { 0.6, 0.15 }, { 1, 1 } })
	emitter.Color = ColorSequence.new(WHITE, WATER)
	emitter.Texture = SPLASH_TEXTURE
	emitter.LightEmission = 0.6
	emitter.Parent = root
	return emitter
end

-- Всплеск у поплавка: count капель; power — во сколько раз быстрее (выше) они летят.
local function splash(bobber: Bobber, count: number, power: number)
	bobber.splash.Speed = NumberRange.new(9 * power, 16 * power)
	burst(bobber.splash, count)
end

-- Два следа на одних точках: мягкая лента и искры поверх (Trail дешевле частиц).
local function makeTrails(
	part: BasePart,
	top: Vector3,
	bottom: Vector3,
	colors: { Color3 },
	prefix: string,
	life: number?
): { Trail }
	local a0 = Instance.new("Attachment")
	a0.Name = `{prefix}TrailTop`
	a0.Position = top
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Name = `{prefix}TrailBottom`
	a1.Position = bottom
	a1.Parent = part
	local trails = {}
	for index, kind in { "Trail", "Sparkle" } do
		local trail = Instance.new("Trail")
		trail.Name = `{prefix}{kind}`
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.FaceCamera = true
		trail.LightInfluence = 0
		trail.MinLength = 0.05
		trail.Color = gradient(colors)
		if index == 1 then
			trail.Lifetime = life or 0.35
			trail.LightEmission = 0.6
			trail.Transparency = numbers({ { 0, 0.15 }, { 1, 1 } })
			trail.WidthScale = numbers({ { 0, 1 }, { 1, 0.1 } })
		else
			trail.Lifetime = (life or 0.35) + 0.2
			trail.LightEmission = 1
			trail.Brightness = 2
			trail.Texture = SPARKLE_TEXTURE
			trail.TextureMode = Enum.TextureMode.Wrap
			trail.TextureLength = 1.4
			trail.Transparency = numbers({ { 0, 0 }, { 1, 1 } })
			trail.WidthScale = numbers({ { 0, 1.6 }, { 1, 0.4 } })
		end
		trail.Parent = part
		table.insert(trails, trail)
	end
	return trails
end

local function setTrails(trails: { Trail }, enabled: boolean)
	for _, trail in trails do
		trail.Enabled = enabled
	end
end

-- Пенный след по воде за поплавком, пока тянем: плоская лента на ватерлинии (waterline —
-- от точки привязки лески вниз до воды), поперёк движения.
local function makeWake(root: BasePart, waterline: number): Trail
	local a0 = Instance.new("Attachment")
	a0.Name = "WakeA"
	a0.Position = Vector3.new(-0.7, -waterline, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "WakeB"
	a1.Position = Vector3.new(0.7, -waterline, 0)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "Wake"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.FaceCamera = false
	trail.Lifetime = 0.6
	trail.MinLength = 0.1
	trail.Color = ColorSequence.new(WHITE)
	trail.Transparency = numbers({ { 0, 0.2 }, { 1, 1 } })
	trail.WidthScale = numbers({ { 0, 1 }, { 1, 2.2 } })
	trail.LightEmission = 0.3
	trail.LightInfluence = 0
	trail.Enabled = false
	trail.Parent = root
	return trail
end

-- Белый контур своего поплавка (во время поклёвки ещё и мигает жёлтой заливкой).
local function makeGlow(model: Model): Highlight
	local glow = Instance.new("Highlight")
	glow.Name = "OwnGlow"
	glow.Adornee = model
	glow.DepthMode = Enum.HighlightDepthMode.Occluded
	glow.OutlineColor = WHITE
	glow.OutlineTransparency = 0
	glow.FillColor = SUN_TOP
	glow.FillTransparency = 1
	glow.Parent = model
	return glow
end

-- «!» над поплавком во время поклёвки: жёлто-оранжевый значок с обводкой, свечение сзади;
-- у своего — крупный, поверх всего, вокруг кружат звёздочки (движение — animateAlert).
-- Гуи сразу наибольшего размера, всё внутри Holder — его UIScale «FxScale» и анимируется.
local function makeAlert(root: BasePart, own: boolean): Alert
	local studs = (if own then FX.AlertStuds else FX.AlertOtherStuds) * FX.AlertRoom
	local pixels = math.round((if own then FX.AlertPixels else FX.AlertOtherPixels) * FX.AlertRoom)
	local gui = Instance.new("BillboardGui")
	gui.Name = "BiteAlert"
	gui.Adornee = root
	gui.AlwaysOnTop = own
	gui.LightInfluence = 0
	gui.MaxDistance = if own then Fx.Range else ALERT_OTHER_DISTANCE
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ClipsDescendants = false
	gui.Size = UDim2.new(studs, pixels, studs, pixels)
	gui.StudsOffset = Vector3.new(0, if own then FX.AlertLift else FX.AlertOtherLift, 0)
	gui.Enabled = false

	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	local scale = Instance.new("UIScale")
	scale.Name = "FxScale"
	scale.Scale = 0
	scale.Parent = holder
	holder.Parent = gui

	local glow = roundFrame(holder, "Glow", 1.3, SUN_TOP, 0.5)
	glow.ZIndex = 1
	local badge = roundFrame(holder, "Badge", 0.86, WHITE, 0)
	badge.ZIndex = 2
	local fill = Instance.new("UIGradient")
	fill.Name = "Fill"
	fill.Color = ColorSequence.new(SUN_TOP, SUN_BOTTOM)
	fill.Rotation = 90
	fill.Parent = badge
	local outline = Instance.new("UIStroke")
	outline.Color = INK
	outline.Thickness = if own then 3 else 2
	outline.Parent = badge
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.AnchorPoint = Vector2.new(0.5, 0)
	gloss.Position = UDim2.fromScale(0.5, 0.07)
	gloss.Size = UDim2.fromScale(0.62, 0.34)
	gloss.BackgroundColor3 = WHITE
	gloss.BackgroundTransparency = 0.55
	gloss.BorderSizePixel = 0
	gloss.ZIndex = 3
	local glossCorner = Instance.new("UICorner")
	glossCorner.CornerRadius = UDim.new(0.5, 0)
	glossCorner.Parent = gloss
	gloss.Parent = badge

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.52)
	label.Size = UDim2.fromScale(0.78, 0.78)
	label.BackgroundTransparency = 1
	label.Text = "!"
	label.TextScaled = false
	label.TextSize = if own then FX.AlertText else FX.AlertOtherText
	label.FontFace = FONT
	label.TextColor3 = WHITE
	label.TextStrokeColor3 = INK
	label.TextStrokeTransparency = 0
	label.ZIndex = 4
	local textOutline = Instance.new("UIStroke")
	textOutline.Name = "Outline"
	textOutline.Color = INK
	textOutline.Thickness = if own then 2.5 else 1.5
	textOutline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	textOutline.Parent = label
	label.Parent = holder

	local stars = {}
	if own then
		for index = 1, FX.AlertStars do
			local star = Instance.new("TextLabel")
			star.Name = `Star{index}`
			star.AnchorPoint = Vector2.new(0.5, 0.5)
			star.Size = UDim2.fromScale(0.3, 0.3)
			star.BackgroundTransparency = 1
			star.Text = if index % 2 == 1 then "⭐" else "✨"
			star.TextScaled = false
			star.TextSize = FX.AlertStarText
			star.TextStrokeTransparency = 1
			star.ZIndex = 5
			star.Parent = holder
			table.insert(stars, star)
		end
	end
	gui.Parent = root
	return {
		gui = gui,
		lift = gui.StudsOffset.Y,
		scale = scale,
		glow = glow,
		badge = badge,
		label = label,
		stars = stars,
	}
end

-- Выскакивание с перелётом (Back Out): 0 → 1 за ALERT_POP секунд.
local ALERT_POP = 0.28
local function backOut(a: number): number
	local c = 1.70158
	local x = a - 1
	return 1 + (c + 1) * x * x * x + c * x * x
end

-- «!» выскакивает, прыгает мячиком, пульсирует жёлтым↔оранжевым, покачивается; звёздочки
-- кружат. age — сколько секунд идёт поклёвка. Частоты ниже 3 Гц (STYLE.md §4: ничего не
-- мигает чаще 3 раз в секунду).
local function animateAlert(alert: Alert, t: number, age: number)
	local pop = backOut(math.clamp(age / ALERT_POP, 0, 1))
	local bounce = math.abs(math.sin(t * 6.5))
	local pulse = 0.5 + 0.5 * math.sin(t * 9)
	alert.gui.StudsOffset = Vector3.new(0, alert.lift + 0.8 * bounce, 0)
	alert.scale.Scale = pop * (1 + 0.25 * pulse) / FX.AlertRoom
	local glow = 1.15 + 0.4 * pulse
	alert.glow.Size = UDim2.fromScale(glow, glow)
	alert.glow.BackgroundTransparency = 0.3 + 0.5 * pulse
	alert.glow.BackgroundColor3 = SUN_TOP:Lerp(SUN_BOTTOM, pulse)
	local tilt = math.sin(t * 11) * 9
	alert.badge.Rotation = tilt
	alert.label.Rotation = tilt
	local count = #alert.stars
	for index, star in alert.stars do
		local angle = t * 2.6 + (index - 1) * 2 * math.pi / count
		star.Position = UDim2.fromScale(0.5 + 0.7 * math.cos(angle), 0.5 + 0.7 * math.sin(angle))
		star.Rotation = math.deg(angle) * 0.5
		star.TextTransparency = 0.15 + 0.15 * math.sin(t * 7 + index * 1.7)
	end
end

local function bobberTemplate(rodId: any): Model?
	local source = bobbersFolder
	if not source then
		return nil
	end
	local template = (typeof(rodId) == "string" and source:FindFirstChild(rodId))
		or source:FindFirstChild(RodConfig.StartRod)
	return if template and template:IsA("Model") then template else nil
end

local function createBobber(tracker: Tracker): Bobber?
	local player = tracker.player
	local template = bobberTemplate(player:GetAttribute("RodId"))
	local parent = folder
	if not template or not parent then
		return nil
	end
	local trove = Trove.new()
	local model = trove:Add(template:Clone())
	model.Name = `Bobber_{player.UserId}`
	local root = model.PrimaryPart
	local lineAttachment = root and root:FindFirstChild("LineAttachment")
	if not root or not lineAttachment or not lineAttachment:IsA("Attachment") then
		trove:Clean()
		return nil
	end
	-- Копия крупнее (ScaleTo — вокруг точки привязки лески); pivot опускается так, что
	-- ватерлиния, как у шаблона, на FloatDepth ниже pivot.
	local floatDepth = finite(model:GetAttribute("FloatDepth")) or DEFAULT_FLOAT_DEPTH
	local waterline = floatDepth -- от точки привязки лески вниз до ватерлинии
	local own = isOwn(tracker)
	local scale = if own then OWN_BOBBER_SCALE else BOBBER_SCALE
	local scaled = pcall(function()
		model:ScaleTo(scale)
	end)
	if scaled then
		waterline = floatDepth * scale
		root.PivotOffset = CFrame.new(0, floatDepth - waterline, 0)
	end
	makeRoom(tracker, 1) -- у поплавка свой ParticleEmitter (брызги)
	local now = os.clock()
	local line = FishingLine.new(model, lineAttachment, root, FX.LineTip, FX.LineFloat, FX.LineColor, FX.LineGlow)
	local bobber: Bobber = {
		player = player,
		own = own,
		trove = trove,
		model = model,
		root = root,
		lineAttachment = lineAttachment,
		line = line,
		beam = line.beam,
		splash = makeSplash(root),
		trails = makeTrails(root, Vector3.new(0, 0.5, 0), Vector3.new(0, -0.5, 0), { SUN_TOP, WHITE }, "Cast", 0.45),
		wake = makeWake(root, waterline),
		glow = if own then makeGlow(model) else nil,
		whoosh = makeSound(root, "Whoosh", SOUND_WHOOSH, 0.35, own),
		splashSound = makeSound(root, "SplashSound", SOUND_SPLASH, 0.5, own),
		pingSound = makeSound(root, "Ping", SOUND_PING, 0.35, own),
		alert = makeAlert(root, own),
		floatDepth = floatDepth,
		state = "Waiting",
		stateSince = now,
		target = Vector3.zero,
		castTime = -math.huge,
		launchAt = 0,
		launched = false,
		position = Vector3.zero,
		landed = false,
		landedAt = 0,
		fresh = false,
		nextSplash = 0,
		nextRipple = 0,
		dip = 0,
		jerks = 0,
		nibbleAt = nil,
		popStart = nil,
		popSplashed = false,
		retractFrom = nil,
		retractStart = 0,
		hooked = nil,
		tip = nil,
		nextTipSearch = 0,
		seed = (player.UserId % 97) * 0.37,
		whipped = false,
		pivotAt = -math.huge,
		pivotKey = "",
		rarity = nil,
		hitsNeeded = nil,
		hits = 0,
		hitAt = 0,
		pullFrom = 0,
		hangFade = 0,
		shadow = nil,
		shadowGone = nil,
	}
	readCast(bobber)
	bobber.position = anchorPosition(bobber, resolveTip(bobber, now))
	-- Заброс видно (поплавок ещё на кончике или летит): свист и след — в миг срыва (stepBobber);
	-- иначе он уже на воде — без них.
	bobber.fresh = Workspace:GetServerTimeNow() - bobber.castTime < FishingConfig.CastFlightTime
	bobber.launched = not bobber.fresh
	setTrails(bobber.trails, false)
	model:PivotTo(CFrame.new(bobber.position))
	model.Parent = parent
	return bobber
end

--------------------------------------------------------------------------------
-- Движение поплавка (каждый кадр, только активные)
--------------------------------------------------------------------------------

-- Полёт дугой, кувыркаясь (FX.CastSpins оборотов); nil — уже долетел. До срыва (замах, alpha < 0)
-- поплавок висит на живом кончике удочки и ходит вместе с ней.
local function flightPose(bobber: Bobber, from: Vector3): (Vector3?, CFrame, number)
	local landing = bobber.castTime + FishingConfig.CastFlightTime
	local span = landing - bobber.launchAt
	local now = Workspace:GetServerTimeNow()
	if now >= landing or span <= 1e-3 then
		return nil, CFrame.identity, 1
	end
	local alpha = (now - bobber.launchAt) / span
	alpha = math.max(alpha, 0)
	local height = math.clamp((bobber.target - from).Magnitude * 0.3, 2, 10)
	local position = from:Lerp(bobber.target, alpha) + Vector3.new(0, height * 4 * alpha * (1 - alpha), 0)
	local path = flat(bobber.target - from)
	local axis = if path.Magnitude > 0.01 then path.Unit:Cross(Vector3.yAxis) else Vector3.xAxis
	return position, CFrame.fromAxisAngle(axis, -FX.CastSpins * 2 * math.pi * alpha), alpha
end

-- Нырок поклёвки 0..1: резкие рывки вниз.
local function biteDip(bobber: Bobber, now: number): number
	return math.abs(math.sin((now + bobber.seed) * FX.BiteSpeed)) ^ 6
end

-- Насколько рыба притопила поплавок, 0..1: рывки поклёвки и своя «примерка» (GetBobberDip).
local function dipOf(bobber: Bobber, now: number): number
	if not bobber.landed or bobber.retractFrom or bobber.hooked then
		return 0
	end
	if bobber.state == "Bite" then
		return biteDip(bobber, now)
	end
	local nibbleAt = bobber.nibbleAt
	if nibbleAt and bobber.state == "Waiting" then
		local k = (now - nibbleAt) / NIBBLE_TIME
		if k >= 0 and k < 1 then
			return math.sin(math.pi * k)
		end
	end
	return 0
end

-- Рыба сорвалась: поплавок подскакивает на POP_HEIGHT и шлёпается обратно на воду.
local function popPose(bobber: Bobber, now: number): (Vector3, CFrame)
	local a = math.clamp((now - (bobber.popStart or now)) / POP_TIME, 0, 1)
	return bobber.target + Vector3.new(0, POP_HEIGHT * 4 * a * (1 - a), 0),
		CFrame.Angles(0, 0, math.sin(a * math.pi) * 0.6)
end

-- Сколько пути к рыбаку поплавок прошёл в борьбе (доля): свой — рывками с каждым попаданием
-- в мини-игре (FX.PullTime с перелётом), чужой (попаданий не видно) — по времени.
local function reelPull(bobber: Bobber, now: number): number
	local since = now - bobber.stateSince
	local needed = bobber.hitsNeeded
	if not needed or needed <= 0 then
		return math.min(FX.ReelPullMax, since * FX.ReelPull)
	end
	local creep = math.min(FX.ReelCreepMax, since * FX.ReelCreep)
	local goal = (FX.ReelPullMax - FX.ReelCreepMax) * math.min(bobber.hits / needed, 1)
	local k = math.clamp((now - bobber.hitAt) / FX.PullTime, 0, 1)
	local c1 = 1.70158
	local eased = 1 + (c1 + 1) * (k - 1) ^ 3 + c1 * (k - 1) ^ 2
	return creep + bobber.pullFrom + (goal - bobber.pullFrom) * eased
end

-- На воде: покачивание (и «примерка»), поклёвка или вытаскивание. Возвращает позицию и наклон.
local function waterPose(bobber: Bobber, from: Vector3, now: number): (Vector3, CFrame)
	local t = now + bobber.seed
	local target = bobber.target
	if bobber.state == "Bite" then
		local dip = biteDip(bobber, now)
		local jitter = math.sin(t * 23) * 0.12
		return target - Vector3.new(jitter, FX.BiteDip * dip + 0.08, 0),
			CFrame.Angles(math.sin(t * 17) * 0.35, 0, math.cos(t * 13) * 0.35)
	elseif bobber.state == "Reeling" then
		-- Поплавок развёрнут осью X к рыбаку (пенный след — поперёк метаний) и качается вбок.
		local toFisher = Vector3.new(from.X, target.Y, from.Z) - target
		local pull = reelPull(bobber, now)
		local direction = if toFisher.Magnitude > 0.01 then toFisher.Unit else Vector3.xAxis
		local side = direction:Cross(Vector3.yAxis)
		local swing = math.sin(t * FX.ReelSpeed) * FX.ReelSwing
		local dip = math.abs(math.sin(t * 11)) * 0.25
		local facing = CFrame.fromMatrix(Vector3.zero, direction, Vector3.yAxis)
		return target + toFisher * pull + side * swing - Vector3.new(0, dip, 0),
			facing * CFrame.Angles(math.sin(t * FX.ReelSpeed) * 0.5, 0, 0)
	end
	local bob = math.sin(t * FX.BobSpeed) * FX.BobAmplitude
	local tilt = CFrame.Angles(math.sin(t * 1.3) * 0.08, 0, math.cos(t * 1.1) * 0.08)
	local plop = now - bobber.landedAt
	if bobber.fresh and plop < FX.PlopTime then
		-- «Плюх»: нырнул, вынырнул с перелётом, закачался, накренившись по полёту (пружина);
		-- обычное покачивание нарастает с нуля — без скачка.
		local decay = math.exp(-FX.PlopDamp * plop)
		local w = 2 * math.pi * FX.PlopHz
		bob = bob * math.min(plop / FX.PlopTime, 1) - FX.Plop * decay * math.sin(w * plop)
		local path = flat(target - from)
		local axis = if path.Magnitude > 0.01 then path.Unit:Cross(Vector3.yAxis) else Vector3.xAxis
		tilt = CFrame.fromAxisAngle(axis, -FX.PlopTilt * decay * math.sin(w * 1.2 * plop + 0.4)) * tilt
	end
	local nibbleAt = bobber.nibbleAt
	if nibbleAt then
		local k = (now - nibbleAt) / NIBBLE_TIME
		if k < 1 then
			bob -= NIBBLE_DIP * math.sin(math.pi * k)
		else
			bobber.nibbleAt = nil
		end
	end
	return target + Vector3.new(0, bob, 0), tilt
end

-- Свой поплавок висит на кончике удочки (замах «сбоку», удочка над плечом): у самой камеры он
-- вышел бы на пол-экрана — ближе HANG_NEAR studs к камере он полупрозрачный (до HANG_FADE у
-- HANG_CLOSE); сорвался с кончика — снова обычный.
local HANG_NEAR, HANG_CLOSE, HANG_FADE = 18, 10, 0.6
local function fadeHanging(bobber: Bobber, hanging: boolean)
	local fade = 0
	local camera = Workspace.CurrentCamera
	if hanging and bobber.own and camera then
		local away = (camera.CFrame.Position - bobber.position).Magnitude
		fade = HANG_FADE * math.clamp((HANG_NEAR - away) / (HANG_NEAR - HANG_CLOSE), 0, 1)
	end
	if fade == bobber.hangFade or (fade > 0 and math.abs(fade - bobber.hangFade) < 0.03) then
		return
	end
	bobber.hangFade = fade
	for _, part in bobber.model:GetDescendants() do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = fade
		end
	end
	local glow = bobber.glow
	if glow then
		glow.OutlineTransparency = fade -- (белый контур тает вместе с ним)
	end
end

-- Спокойные круги рисуем у своего поплавка и у рыбаков не дальше Fx.AmbientRange.
local function ambientNear(bobber: Bobber): boolean
	if bobber.own then
		return true
	end
	local viewer = viewerPosition()
	return viewer == nil or (viewer - bobber.position).Magnitude <= Fx.AmbientRange
end

-- Поплавок на воде: приводнение, круги, брызги (только если это видно отсюда — near).
local function updateWater(bobber: Bobber, now: number, near: boolean)
	local tracker = trackers[bobber.player]
	if not tracker then
		return
	end
	local lift = Vector3.new(0, FX.RingLift, 0)
	if not bobber.landed then
		bobber.landed = true
		bobber.landedAt = now
		setTrails(bobber.trails, false)
		bobber.nextRipple = now + Fx.RippleEvery
		if bobber.fresh and near then
			-- «плюх»: брызги, низкий столбик воды, круги и звук повыше обычного всплеска
			splash(bobber, SPLASH.landing, 1)
			play(bobber.splashSound, 1.35)
			ringBurst(tracker, bobber, waterUnder(bobber) + lift, RING.landing, 3, 0.14)
			spout(tracker, waterUnder(bobber), 1.8)
		end
	end
	local state = bobber.state
	local rippleEvery = if state == "Waiting"
		then Fx.RippleEvery
		elseif state == "Reeling" then Fx.ReelRippleEvery
		else nil
	if rippleEvery and now >= bobber.nextRipple then
		bobber.nextRipple = now + rippleEvery
		if near and ambientNear(bobber) and liveRings(tracker) < Fx.MaxRings then
			local look = if state == "Reeling" then RING.reel else RING.ripple
			ringBurst(tracker, bobber, waterUnder(bobber) + lift, look, 1, 0)
		end
	end
	if state == "Bite" then
		-- Рывок: нырок прошёл BiteJerk вниз — брызги; каждый второй — ещё и круг.
		local dip = biteDip(bobber, now)
		if bobber.dip < FX.BiteJerk and dip >= FX.BiteJerk then
			bobber.jerks += 1
			if near then
				splash(bobber, SPLASH.jerk, 1)
				if bobber.jerks % 2 == 0 then
					ringBurst(tracker, bobber, waterUnder(bobber, bobber.target) + lift, RING.jerk, 1, 0)
				end
			end
		end
		bobber.dip = dip
	elseif state == "Reeling" and now >= bobber.nextSplash then
		bobber.nextSplash = now + Fx.ReelSprayEvery
		if near then
			splash(bobber, SPLASH.reel, 0.8)
		end
	end
end

-- Свой поплавок во время поклёвки: жёлтая заливка мигает (FX.BiteGlowRate Гц).
local function setGlowFill(bobber: Bobber, now: number?)
	local glow = bobber.glow
	if not glow then
		return
	end
	if now then
		glow.FillTransparency = 0.575 + 0.225 * math.cos(2 * math.pi * FX.BiteGlowRate * now)
	elseif glow.FillTransparency ~= 1 then
		glow.FillTransparency = 1
	end
end

local function destroyBobber(tracker: Tracker)
	local bobber = tracker.bobber
	if bobber then
		tracker.bobber = nil
		active[bobber] = nil
		bobber.hooked = nil
		for effect in table.clone(tracker.effects) do
			if effect.owner == bobber then
				endEffect(effect)
			end
		end
		bobber.trove:Clean()
		if isOwn(tracker) then
			updateCamera()
		end
	end
end

-- След кончика удочки при броске (FishingLine.whip): от FisherPoses.Timing.Swing до срыва
-- поплавка (тот же миг, что фаза Release FisherAnimController) до FX.WhipAfter после него.
local function startWhip(bobber: Bobber, tip: Attachment)
	local tracker = trackers[bobber.player]
	if not tracker then
		return
	end
	bobber.whipped = true
	local left = math.max(bobber.launchAt - Workspace:GetServerTimeNow(), 0) + FX.WhipAfter
	local effect = newEffect(tracker, left + 0.2, bobber)
	effect.instances = FishingLine.whip(tip)
	local trail = effect.instances[1]
	task.delay(left, function()
		if trail and trail:IsA("Trail") and trail.Parent then
			trail.Enabled = false
		end
	end)
end

-- Тень рыбы под поплавком (FishShadow): своя всегда, чужая — ближе Fx.AmbientRange; рыба
-- поймана — исчезает, сорвалась или леску смотали — уплывает прочь.
local function stepShadow(bobber: Bobber, now: number, from: Vector3)
	local shadow = bobber.shadow
	local gone = bobber.shadowGone
	if not shadow then
		local parent = folder
		if gone or not bobber.landed or not parent or not ambientNear(bobber) then
			return
		end
		local made = FishShadow.new(parent, bobber.own, bobber.seed, waterUnder(bobber, bobber.target))
		bobber.trove:Add(function()
			FishShadow.destroy(made)
		end)
		bobber.shadow = made
		shadow = made
	end
	local s = shadow :: FishShadow.Shadow
	local state = bobber.state
	-- «Прочь от рыбака» — от его тела (кончик удочки бывает и над водой, дальше поплавка).
	local character = bobber.player.Character
	local body = character and character.PrimaryPart
	if body then
		from = body.Position
	end
	if gone then
		FishShadow.step(s, now, gone, now, waterUnder(bobber, bobber.target), from, 0, nil, 0, s.scale)
	elseif state == "Waiting" then
		local nibbleAt = bobber.nibbleAt
		local nibble = if nibbleAt then math.clamp((now - nibbleAt) / NIBBLE_TIME, 0, 1) else nil
		FishShadow.step(s, now, "wait", bobber.landedAt, waterUnder(bobber, bobber.target), from, 0, nibble, 0, 1)
	elseif state == "Bite" then
		local water = waterUnder(bobber, bobber.target)
		FishShadow.step(s, now, "bite", bobber.stateSince, water, from, biteDip(bobber, now), nil, 0, 1)
	else
		local swing = math.sin((now + bobber.seed) * FX.ReelSpeed)
		local scale = if bobber.own then FX.ShadowScale[bobber.rarity or ""] or 1 else FX.ShadowOther
		FishShadow.step(s, now, "reel", bobber.stateSince, waterUnder(bobber), from, 0, nil, swing, scale)
	end
end

stepBobber = function(bobber: Bobber, now: number)
	local tip = resolveTip(bobber, now)
	local near = isNear(bobber.position)
	-- (далёкий — дальше Fx.Range — без лески: её там не видно, а Beam рисуется через всю лагуну)
	bobber.beam.Enabled = tip ~= nil and near
	if bobber.hooked then
		return -- на крючке рыба в прыжке: поплавок ведёт она (startLeap)
	end
	local from = anchorPosition(bobber, tip)
	local tilt = CFrame.identity
	local lineMode, lineAmount = "retract", 0

	local retractFrom = bobber.retractFrom
	if retractFrom then
		local alpha = (now - bobber.retractStart) / RETRACT_TIME
		if alpha >= 1 then
			local tracker = trackers[bobber.player]
			if tracker then
				destroyBobber(tracker) -- смотали: поплавок и леска исчезают
			end
			return
		end
		if alpha < 0 then
			bobber.position, tilt = popPose(bobber, now) -- сначала подскакивает (рыба сорвалась)
			lineMode = "slack" -- леска ослабла (FishingLine: слабина после вспышки)
		else
			if bobber.popStart and not bobber.popSplashed then
				bobber.popSplashed = true -- шлёпнулся обратно
				if near then
					splash(bobber, SPLASH.pop, 0.9)
				end
			end
			local eased = alpha * alpha
			bobber.position = retractFrom:Lerp(from, eased) + Vector3.new(0, 2 * math.sin(alpha * math.pi), 0)
		end
	else
		local flying, spin, progress = flightPose(bobber, from)
		local popStart = bobber.popStart
		if flying then
			bobber.position = flying
			tilt = spin
			local serverNow = Workspace:GetServerTimeNow()
			-- Бросок: след кончика удочки — с началом взмаха (Swing до срыва).
			if
				not bobber.whipped
				and bobber.fresh
				and near
				and tip
				and serverNow >= bobber.launchAt - FisherPoses.Timing.Swing
			then
				startWhip(bobber, tip)
			end
			-- Сорвался с кончика (CastTime; до того висел на нём — замах): свист и след.
			if not bobber.launched and serverNow >= bobber.launchAt then
				bobber.launched = true
				if near then
					setTrails(bobber.trails, true)
					play(bobber.whoosh)
				end
			end
			lineMode = if bobber.launched then "flight" else "hang"
			lineAmount = progress
			fadeHanging(bobber, not bobber.launched)
		elseif popStart and now - popStart < POP_TIME then
			bobber.position, tilt = popPose(bobber, now)
			lineMode = "slack"
		else
			bobber.position, tilt = waterPose(bobber, from, now)
			updateWater(bobber, now, near)
			local state = bobber.state
			if state == "Reeling" then
				lineMode = "taut"
				lineAmount = math.abs(math.sin((now + bobber.seed) * FX.ReelSpeed))
			else
				lineMode = if state == "Bite" then "bite" else "slack"
				lineAmount = dipOf(bobber, now)
			end
		end
		-- Далёкие поплавки (дальше Fx.Range) — без анимации «!» и лески: их почти не видно.
		if near and bobber.alert.gui.Enabled then
			animateAlert(bobber.alert, now, now - bobber.stateSince)
		end
		if bobber.state == "Bite" then
			setGlowFill(bobber, now)
		end
	end
	-- Далёкий поплавок переставляем раз в FAR_PIVOT с (или сразу, когда сменилось состояние):
	-- PivotTo — это запись CFrame каждой его детали.
	local key = `{bobber.state}{if retractFrom then "r" else ""}`
	if near or key ~= bobber.pivotKey or now - bobber.pivotAt >= FAR_PIVOT then
		bobber.pivotKey = key
		bobber.pivotAt = now
		bobber.model:PivotTo(CFrame.new(bobber.position) * tilt)
	end
	if near then
		FishingLine.step(bobber.line, now, lineMode, from, bobber.root.Position, lineAmount)
		stepShadow(bobber, now, from)
	end
end

local function activate(bobber: Bobber)
	active[bobber] = true
	ensureFrame()
end

--------------------------------------------------------------------------------
-- Состояние рыбалки игрока
--------------------------------------------------------------------------------

local function setBobberState(bobber: Bobber, state: string)
	if bobber.state == state then
		return
	end
	if bobber.state == "Bite" and state == "Reeling" then
		FishingLine.hook(bobber.line, os.clock()) -- подсечка: леска на миг белая, в струну
	end
	bobber.state = state
	bobber.stateSince = os.clock()
	bobber.nextSplash = 0
	bobber.nextRipple = bobber.stateSince + (if state == "Reeling" then 0.2 else Fx.RippleEvery)
	bobber.dip = 0
	bobber.jerks = 0
	bobber.nibbleAt = nil
	bobber.alert.gui.Enabled = state == "Bite"
	bobber.alert.scale.Scale = 0
	bobber.wake.Enabled = state == "Reeling"
	if state ~= "Bite" then
		setGlowFill(bobber, nil)
	end
	local tracker = trackers[bobber.player]
	if state == "Bite" and tracker and isNear(bobber.position) then
		splash(bobber, SPLASH.bite, 1.3)
		play(bobber.splashSound, 1.15)
		play(bobber.pingSound)
		ringBurst(
			tracker,
			bobber,
			waterUnder(bobber, bobber.target) + Vector3.new(0, FX.RingLift, 0),
			RING.bite,
			3,
			0.12
		)
	end
end

local function startRetract(tracker: Tracker, bobber: Bobber)
	local now = os.clock()
	local popStart = bobber.popStart
	if popStart and now - popStart < POP_TIME then
		-- Рыба только что сорвалась: поплавок досмотрит свой подскок, потом сматывается.
		bobber.retractFrom = bobber.target
		bobber.retractStart = popStart + POP_TIME
	else
		bobber.retractFrom = bobber.position
		bobber.retractStart = now
	end
	bobber.alert.gui.Enabled = false
	bobber.wake.Enabled = false
	setGlowFill(bobber, nil)
	bobber.shadowGone = bobber.shadowGone or "gone" -- тень уплывает (сорвалась — уже "lost")
	fadeOwned(tracker, bobber)
end

local function onStateChanged(player: Player, tracker: Tracker)
	local state = player:GetAttribute("FishingState")
	local fishing = state == "Waiting" or state == "Bite" or state == "Reeling"
	local bobber = tracker.bobber
	if fishing then
		if bobber and (bobber.retractFrom or bobber.hooked) then
			-- Новый заброс, пока старый поплавок ещё сматывался (или летел с рыбой: прыжок
			-- долетит без него).
			destroyBobber(tracker)
			bobber = nil
		end
		if not bobber then
			bobber = createBobber(tracker)
			tracker.bobber = bobber
		end
		if bobber then
			setBobberState(bobber, state :: string)
			activate(bobber)
		end
	elseif bobber and not bobber.retractFrom and not bobber.hooked then
		startRetract(tracker, bobber)
	end
	if isOwn(tracker) then
		updateCamera()
	end
end

-- Новый заброс без возврата в "Idle" (или атрибуты пришли позже состояния).
local function onCastChanged(tracker: Tracker)
	local bobber = tracker.bobber
	if bobber and not bobber.retractFrom and not bobber.hooked then
		readCast(bobber)
	end
end

--------------------------------------------------------------------------------
-- Улов: прыжок рыбы, вспышка и ореол, табличка, искры, столб света, конфетти
--------------------------------------------------------------------------------

local function fishTemplate(id: string?, mutation: string?): Model?
	local source = fishFolder
	local variants = id and source and source:FindFirstChild(id)
	if not variants then
		return nil
	end
	local model = variants:FindFirstChild(mutation or "Normal") or variants:FindFirstChild("Normal")
	return if model and model:IsA("Model") and model.PrimaryPart then model else nil
end

-- Копия модели рыбы для эффекта: закреплена, без столкновений, запросов и теней.
local function cloneFish(template: Model, name: string): Model
	local model = template:Clone()
	model.Name = name
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
		end
	end
	return model
end

-- Где сервер повесит эту рыбу над головой (FishingService.holdFish): центр рамки модели (в scale
-- раз крупнее — FishingConfig.HeldScale) над макушкой с зазором HeldFishGap, оси модели — оси
-- головы. center / size — рамка модели в натуральную величину (center — от её pivot).
local function heldPlacement(head: BasePart, center: Vector3, size: Vector3, scale: number): CFrame
	local lift = head.Size.Y / 2 + FishingConfig.HeldFishGap + size.Y * scale / 2
	return CFrame.new(0, lift, 0) * CFrame.new(-center * scale)
end

-- Рамка модели: центр относительно pivot и размер.
local function fishBox(model: Model): (Vector3, Vector3)
	local boxCFrame, boxSize = model:GetBoundingBox()
	return model:GetPivot():PointToObjectSpace(boxCFrame.Position), boxSize
end

-- Во сколько раз рыба над головой крупнее модели (как FishingService.holdFish: по редкости, не
-- длиннее HeldMaxLength; пришла HeldFish — её атрибут Scale).
local function heldScale(rarity: string, size: Vector3): number
	local scale = FishingConfig.HeldScale[rarity] or 1
	local length = math.max(size.X, size.Z)
	if length > 0 then
		scale = math.min(scale, FishingConfig.HeldMaxLength / length)
	end
	return math.max(scale, 1)
end

-- Точка на воде, откуда выпрыгивает (куда ныряет) рыба: под поплавком, без поплавка — цель
-- заброса.
local function waterOrigin(tracker: Tracker): Vector3?
	local bobber = tracker.bobber
	if bobber then
		return waterUnder(bobber, bobber.retractFrom or bobber.position)
	end
	local target = tracker.player:GetAttribute("BobberTarget")
	return if typeof(target) == "Vector3" then target else nil
end

local function setHidden(model: Model, hidden: boolean)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

local function sparkleEmitter(name: string, colors: { Color3 }, rate: number, peak: number?): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Rate = rate
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(0.8, 2.4)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 1.5, 0)
	emitter.Size = numbers({ { 0, 0 }, { 0.2, peak or 0.55 }, { 1, 0 } })
	emitter.Transparency = numbers({ { 0, 0.05 }, { 0.75, 0.2 }, { 1, 1 } })
	emitter.Color = gradient(colors)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-200, 200)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Texture = SPARKLE_TEXTURE
	return emitter
end

-- Искры вокруг рыбы над головой, пока она там (FishingRules.HoldFishTime): у редкой и выше —
-- цвета редкости, у рыбы с мутацией — цвета мутации (и не реже Fx.MutationAuraRate);
-- неоновая ещё светится голубым. Свет (PointLight) — только у своей рыбы: он ходит с рыбаком,
-- а подвижный свет пересчитывает свою долю освещения каждый кадр (v3 fix F9); чужая
-- светится одним неоном.
local function aura(tracker: Tracker, held: Model, rarity: string, mutation: string?)
	local body = held.PrimaryPart
	local mutationStyle = if mutation then UIConfig.Mutations[mutation] else nil
	local rate = Fx.AuraRate[rarity]
	if mutationStyle then
		rate = math.max(rate or 0, Fx.MutationAuraRate)
	end
	if not rate or not body then
		return
	end
	makeRoom(tracker, 1)
	local effect = newEffect(tracker, FishingRules.HoldFishTime(rarity) + 0.3)
	effect.priority = 1
	local colors = rarityColors(rarity)
	if mutationStyle then
		colors = if mutation == "Rainbow" then UIConfig.Rainbow else { WHITE, mutationStyle.Top, mutationStyle.Bottom }
	end
	local emitter = sparkleEmitter("RarityAura", colors, rate, if mutation == "Gold" then 0.7 else 0.55)
	emitter.Parent = body
	burst(emitter, 14)
	effect.emitter = emitter
	table.insert(effect.instances, emitter)
	local style = UIConfig.Rarity[rarity]
	local light: PointLight? = nil
	if mutation == "Neon" and mutationStyle then
		light = Instance.new("PointLight")
		light.Color = mutationStyle.Top
		light.Range = 12
		light.Brightness = 3
	elseif style and Fx.AuraRate[rarity] then
		light = Instance.new("PointLight")
		light.Color = style.Top
		light.Range = 9
		light.Brightness = 1.6
	end
	if light and not isOwn(tracker) then
		light:Destroy()
		light = nil
	end
	if light then
		light.Name = "RarityGlow"
		light.Shadows = false
		light.Parent = body
		table.insert(effect.instances, light)
	end
end

-- Вспышка: неоновый шар в центре рыбы раздувается и гаснет.
local function popBall(tracker: Tracker, center: Vector3, color: Color3)
	local parent = folder
	if not parent then
		return
	end
	local part = quietPart("Pop", Vector3.new(0.2, 0.2, 0.2), CFrame.new(center))
	part.Shape = Enum.PartType.Ball
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = 0.3
	part.Parent = parent
	local effect = newEffect(tracker, POP_FADE + 0.05)
	table.insert(effect.instances, part)
	tween(part, TweenInfo.new(POP_GROW, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(POP_SIZE, POP_SIZE, POP_SIZE),
	})
	tween(part, TweenInfo.new(POP_FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 })
end

-- Ореол: кольцо лицом к камере (BillboardGui) вокруг рыбы над головой растёт (до to studs,
-- по умолчанию HALO_TO) и тает.
local function halo(tracker: Tracker, body: BasePart, center: Vector3, inner: Color3, to: number?)
	local parent = folder
	if not parent then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Halo"
	gui.Adornee = body
	gui.StudsOffsetWorldSpace = center - body.Position
	gui.Size = UDim2.fromScale(HALO_FROM, HALO_FROM)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.MaxDistance = Fx.Range
	gui.ClipsDescendants = false
	local outerStroke = ringStroke(roundFrame(gui, "Outer", 0.96, WHITE, 1), WHITE, 4)
	local innerStroke = ringStroke(roundFrame(gui, "Inner", 0.84, inner, 1), inner, 3)
	gui.Parent = parent
	local effect = newEffect(tracker, HALO_TIME + 0.05)
	table.insert(effect.instances, gui)
	tween(gui, TweenInfo.new(HALO_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(to or HALO_TO, to or HALO_TO),
	})
	local fade = TweenInfo.new(HALO_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
	tween(outerStroke, fade, { Transparency = 1 })
	tween(innerStroke, fade, { Transparency = 1 })
end

-- «Звезда» удара: тонкие лучи (белые и цвета редкости) выстреливают из-за рыбы наружу и гаснут
-- за FX.BurstTime — чёткий удар в точке рыбы (BillboardGui в studs: с расстоянием мельчает, как
-- сама рыба; ничего не заливает экран).
local function starBurst(tracker: Tracker, body: BasePart, center: Vector3, size: Vector3, rarity: string)
	local parent = folder
	if not parent then
		return
	end
	local colors = rarityColors(rarity)
	local reach = math.max(size.X, size.Y, size.Z) * FX.BurstReach
	local gui = Instance.new("BillboardGui")
	gui.Name = "Burst"
	gui.Adornee = body
	gui.StudsOffsetWorldSpace = center - body.Position
	gui.Size = UDim2.fromScale(reach, reach)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.MaxDistance = Fx.Range
	gui.ClipsDescendants = false
	local hole = 0.25 -- лучи начинаются за краем рыбы (доля размера звезды)
	local grow = TweenInfo.new(FX.BurstTime * 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fade = TweenInfo.new(
		FX.BurstTime * 0.65,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In,
		0,
		false,
		FX.BurstTime * 0.35
	)
	for index = 1, FX.BurstRays do
		local angle = (index - 1) * 360 / FX.BurstRays + 9
		local r = math.rad(angle)
		local dx, dy = math.sin(r), -math.cos(r)
		local long = if index % 2 == 1 then 0.24 else 0.15
		local ray = Instance.new("Frame")
		ray.Name = `Ray{index}`
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.BorderSizePixel = 0
		ray.BackgroundColor3 = if index % 2 == 1 then WHITE else colors[1 + (index // 2) % #colors]
		ray.Rotation = angle
		ray.Position = UDim2.fromScale(0.5 + hole * dx, 0.5 + hole * dy)
		ray.Size = UDim2.fromScale(0.028, 0.01)
		ray.Parent = gui
		local mid = hole + long / 2
		tween(
			ray,
			grow,
			{ Size = UDim2.fromScale(0.028, long), Position = UDim2.fromScale(0.5 + mid * dx, 0.5 + mid * dy) }
		)
		local out = mid + long * 0.45
		tween(ray, fade, {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(0.01, long * 0.5),
			Position = UDim2.fromScale(0.5 + out * dx, 0.5 + out * dy),
		})
	end
	gui.Parent = parent
	local effect = newEffect(tracker, FX.BurstTime + 0.05)
	table.insert(effect.instances, gui)
end

local function plateLabel(
	parent: Instance,
	name: string,
	text: string,
	box: { number },
	outline: number,
	italic: boolean?
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = UDim2.fromScale(box[1], box[2])
	label.Size = UDim2.fromScale(box[3], box[4])
	label.BackgroundTransparency = 1
	label.FontFace = if italic
		then Font.new(UIConfig.Font.Family, Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
		else PLATE_FONT
	label.Text = text
	label.TextColor3 = WHITE
	label.TextScaled = true
	label.TextStrokeColor3 = INK
	label.TextStrokeTransparency = 1 -- (the UIStroke outlines it)
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Outline"
	stroke.Color = INK
	stroke.Thickness = outline
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
	label.Parent = parent
	return label
end

-- Спрятанная своя табличка выскакивает (0 → 1, Back Out) через delay секунд; уже видна — ничего.
-- true — выскочила сейчас.
local function revealPlate(gui: BillboardGui, delay: number): boolean
	if gui.Enabled or gui.Parent == nil then
		return false
	end
	gui.Enabled = true
	local plate = gui:FindFirstChild("Plate")
	local scale = plate and plate:FindFirstChild("FxScale")
	if scale and scale:IsA("UIScale") then
		scale.Scale = 0
		tween(
			scale,
			TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, delay),
			{ Scale = 1 }
		)
	end
	return true
end

--[[
	Своя табличка (справа от рыбы над головой) не заходит на колонку кнопок HUD «САДОК» / «ДОМОЙ»
	(Этап 3, C-R2-01: на планшете и маленьком телефоне «САДОК» стоит как раз на высоте рыбы, и
	«ЛЕГЕНДАРНАЯ» / цена мифической уходили под него). Справа от рыбы, если там до кнопок (с их
	обводкой) и края экрана ≥ 16 px; иначе слева (карточки улова там уже нет); иначе там, где
	просторнее, — меньше, не мельче PLATE_FIT.minScale. Плашки статуса с кошельком — над рыбой
	(камера с трофеем выше, FX.TrophyCamera), но на телефоне строка кошелька с доходом «+$46/с»
	почти касалась слова редкости: табличка опускается, чтобы её верх был ≥ 16 px под ней (не
	больше чем на полвысоты). FishingLayout.plateFit: прямоугольник таблички на экране — studs ×
	пиксели на её глубине + пиксели, как у BillboardGui, и её ход PLATE_FIT.sway. Только в момент,
	когда табличка выскакивает или подпрыгивает (не каждый кадр): камера с трофеем над головой
	стоит, колонка и кошелёк — тоже.
]]
local function fitOwnPlate(gui: BillboardGui)
	local camera = Workspace.CurrentCamera
	local hud = hudGui
	local adornee = gui.Adornee
	if not camera or not hud or not adornee or not adornee:IsA("BasePart") or camera.ViewportSize.Y < 1 then
		return
	end
	local point = camera:WorldToScreenPoint(adornee.Position + gui.StudsOffsetWorldSpace)
	if point.Z <= 0.05 then
		return
	end
	local perStud = camera.ViewportSize.Y / (2 * point.Z * math.tan(math.rad(camera.FieldOfView) / 2))
	-- Кнопки колонки (сбоку) и плашки статуса (сверху) — с их обводкой (UIStroke у Lip) и подписью
	-- чуть шире кнопки; ряд по центру (кошелёк «💵 $0 +$4/с» в широкой рамке) — по содержимому.
	local function boxes(name: string): { FishingLayout.Rect }
		local list = {}
		local holder = hud:FindFirstChild(name)
		if holder and holder:IsA("GuiObject") and holder.Visible then
			for _, item in holder:GetChildren() do
				if item:IsA("GuiObject") and item.Visible then
					local lip = item:FindFirstChild("Lip")
					local stroke = lip and lip:FindFirstChildOfClass("UIStroke")
					local at, size = item.AbsolutePosition, item.AbsoluteSize
					local pad = (if stroke then stroke.Thickness else 0) + size.X * 0.02
					local left, right = at.X, at.X + size.X
					local row = item:FindFirstChildOfClass("UIListLayout")
					if
						row
						and row.FillDirection == Enum.FillDirection.Horizontal
						and row.HorizontalAlignment == Enum.HorizontalAlignment.Center
					then
						local width, count = 0, 0
						for _, child in item:GetChildren() do
							if child:IsA("GuiObject") and child.Visible then
								width += child.AbsoluteSize.X
								count += 1
							end
						end
						width += math.max(count - 1, 0) * (row.Padding.Scale * size.X + row.Padding.Offset)
						left, right = (left + right - width) / 2, (left + right + width) / 2
					end
					table.insert(list, FishingLayout.rect(left - pad, at.Y - pad, right + pad, at.Y + size.Y + pad))
				end
			end
		end
		return list
	end
	local origin, screen = hud.AbsolutePosition, hud.AbsoluteSize
	local reach = math.abs(gui.StudsOffset.X)
	local side, scale, drop = FishingLayout.plateFit(
		Vector2.new(point.X, point.Y),
		reach * perStud,
		NAMEPLATE_STUDS.X * perStud + NAMEPLATE_PIXELS.X,
		NAMEPLATE_STUDS.Y * perStud + NAMEPLATE_PIXELS.Y,
		PLATE_FIT.sway * perStud,
		boxes("RightButtons"),
		boxes("Status"),
		FishingLayout.rect(origin.X, origin.Y, origin.X + screen.X, origin.Y + screen.Y),
		PLATE_FIT.minScale
	)
	gui.StudsOffset = Vector3.new(side * reach, -drop / perStud, 0)
	gui.SizeOffset = Vector2.new(side * 0.5, 0)
	gui.Size = UDim2.new(
		NAMEPLATE_STUDS.X * scale,
		math.round(NAMEPLATE_PIXELS.X * scale),
		NAMEPLATE_STUDS.Y * scale,
		math.round(NAMEPLATE_PIXELS.Y * scale)
	)
end

-- Табличка над рыбой (видят все, пока рыба над головой): редкость (с редкой и выше: белое → цвет
-- редкости, мифическая — переливающейся радугой), название белым, мутация её цветом и цена
-- наклонными жёлтыми цифрами; у обычной — только название и цена, крупнее (v3 fix WOW-5: соседи
-- видят, что за рыба). UI v5: надпись над миром как у образца — без плашки, тёмная обводка. Всё берётся из
-- атрибутов модели (FishId, Rarity, Mutation, Value — их ставит FishingService), поэтому
-- годится и для рыб на витринах базы (Этап 3). Размер — studs + пиксели (издалека читается).
-- У самого рыбака табличка не над рыбой, а справа от неё: сверху экрана — плашки статуса и
-- кошелёк, они закрыли бы её; справа тесно (кнопка «САДОК» на высоте рыбы) — слева или меньше
-- (fitOwnPlate, когда она выскакивает).
local function nameplate(tracker: Tracker, held: Model, rarity: string, event: FxEvent)
	local style = UIConfig.Rarity[rarity]
	local body = held.PrimaryPart
	local parent = folder
	if not style or not body or not parent then
		return
	end
	local common = rarity == "Common"
	local box, size = held:GetBoundingBox()
	local fishId = held:GetAttribute("FishId")
	local def = FishingRules.GetFish(if typeof(fishId) == "string" then fishId else event.id or "")
	local rarityDef = FishingRules.GetRarity(rarity)
	local mutationAttr = held:GetAttribute("Mutation")
	local mutation = if typeof(mutationAttr) == "string" then mutationAttr else event.mutation
	local value = finite(held:GetAttribute("Value"))

	local gui = Instance.new("BillboardGui")
	gui.Name = "Nameplate"
	gui.Adornee = body
	gui.Size = UDim2.new(NAMEPLATE_STUDS.X, NAMEPLATE_PIXELS.X, NAMEPLATE_STUDS.Y, NAMEPLATE_PIXELS.Y)
	local center = box.Position - body.Position
	if isOwn(tracker) then
		-- Левый край таблички — в 0.4 stud правее рыбы (смещение в осях камеры), по центру рыбы.
		gui.StudsOffsetWorldSpace = center
		gui.StudsOffset = Vector3.new(math.max(size.X, size.Z) / 2 + 0.4, 0, 0)
		gui.SizeOffset = Vector2.new(0.5, 0)
	else
		-- Низ таблички — в 0.4 stud над рыбой.
		gui.StudsOffsetWorldSpace = center + Vector3.new(0, size.Y / 2 + 0.4, 0)
		gui.SizeOffset = Vector2.new(0, 0.5)
	end
	gui.MaxDistance = Fx.Range
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.ClipsDescendants = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.AnchorPoint = Vector2.new(0.5, 1)
	plate.Position = UDim2.fromScale(0.5, 1)
	plate.Size = UDim2.fromScale(1, 1)
	plate.BackgroundTransparency = 1
	local scale = Instance.new("UIScale")
	scale.Name = "FxScale"
	scale.Scale = 0
	scale.Parent = plate
	plate.Parent = gui

	-- (обычная рыба: без строки редкости — название и цена на её месте, крупнее)
	local fill: UIGradient? = nil
	if not common then
		local title =
			plateLabel(plate, "Rarity", upper(if rarityDef then rarityDef.Name else rarity), { 0, 0, 1, 0.42 }, 3)
		local gradientFill = Instance.new("UIGradient")
		gradientFill.Name = "Fill"
		gradientFill.Rotation = if style.Rainbow then 0 else 90
		gradientFill.Color = if style.Rainbow
			then gradient(UIConfig.Rainbow)
			else gradient({ WHITE, style.Top, style.Bottom })
		gradientFill.Parent = title
		fill = gradientFill
	end
	local nameBox = if common then { 0.03, 0.18, 0.94, 0.44 } else { 0.05, 0.4, 0.9, 0.3 }
	plateLabel(plate, "FishName", if def then def.Name else "", nameBox, 2.5)
	local mutationDef = if mutation then FishingRules.GetMutation(mutation) else nil
	local mutationStyle = if mutation then UIConfig.Mutations[mutation] else nil
	local row = if common then 0.62 else 0.7
	local rowH = if common then 0.36 else 0.3
	local priceBox = if mutationDef then { 0.5, row, 0.48, rowH } else { 0.2, row, 0.6, rowH }
	if mutationDef and mutationStyle then
		local tag = plateLabel(
			plate,
			"Mutation",
			`{mutationStyle.Icon} {mutationDef.Name} ×{mutationDef.Multiplier}`,
			{ 0.02, row, 0.48, rowH },
			2
		)
		tag.TextColor3 = mutationStyle.Top
	end
	if value then
		local price = plateLabel(plate, "Price", `💰 {FishingRules.FormatCoins(value)}`, priceBox, 2, true)
		price.TextColor3 = UIConfig.BillboardYellow.Top
	end
	gui.Parent = parent
	local life = tracker.life
	if life and life.held == held then
		FishLife.plate(life.life, gui) -- шлепки рыбы табличку не трясут, она покачивается сама
	end

	local effect = newEffect(tracker, FishingRules.HoldFishTime(rarity) + 0.3)
	table.insert(effect.instances, gui)
	local stops: { () -> () } = {}
	effect.onEnd = function()
		for _, stop in stops do
			stop()
		end
	end
	-- Рыбу убрали (трофей снят): табличка не висит без неё ни кадра — там, где была рыба (точка в
	-- Terrain), «выдыхает» до 0.8 и тает за PLATE_OUT с, потом уходит вместе с эффектом (SIMC-C2-06).
	local gone: RBXScriptConnection? = nil
	gone = held.AncestryChanged:Connect(function()
		if effect.done or held:IsDescendantOf(Workspace) then
			return
		end
		if gone then
			gone:Disconnect()
		end
		local spot = Instance.new("Attachment")
		spot.Name = "NameplateSpot"
		spot.WorldPosition = body.Position
		spot.Parent = Workspace.Terrain
		table.insert(effect.instances, spot)
		gui.Adornee = spot
		local out = TweenInfo.new(PLATE_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(scale, out, { Scale = 0.8 * scale.Scale })
		for _, item in plate:GetDescendants() do
			if item:IsA("TextLabel") then
				tween(item, out, { TextTransparency = 1 })
			elseif item:IsA("UIStroke") then
				tween(item, out, { Transparency = 1 })
			end
		end
		cancelThread(effect.thread)
		effect.thread = task.delay(PLATE_OUT + 0.02, function()
			effect.thread = nil
			endEffect(effect)
		end)
	end)
	table.insert(stops, function()
		if gone then
			gone:Disconnect()
		end
	end)
	local hud = hudGui
	if isOwn(tracker) and hud and hud:GetAttribute("CounterHold") ~= nil then
		-- Своя табличка ждёт, пока улов на экране (HUD держит CounterHold): под заголовком она
		-- повторяла бы его слово, из-за карточки торчала бы готовая цена, пока та ещё считает.
		-- Выскакивает на «повторе» трофея (ReplayOwnTrophy) как новое; не было его (карточку
		-- закрыли иначе) — через PLATE_AFTER_CARD после того, как счётчик отпустили.
		gui.Enabled = false
		local waiting = hud:GetAttributeChangedSignal("CounterHold"):Connect(function()
			if hud:GetAttribute("CounterHold") == nil then
				task.delay(PLATE_AFTER_CARD, function()
					if not effect.done and not gui.Enabled then
						fitOwnPlate(gui)
						revealPlate(gui, 0)
					end
				end)
			end
		end)
		table.insert(stops, function()
			waiting:Disconnect()
		end)
	else
		if isOwn(tracker) then
			fitOwnPlate(gui)
		end
		tween(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, 0.12), { Scale = 1 })
	end
	if style.Rainbow and fill then
		-- Радуга переливается: градиент ездит туда-обратно (твин, без соединений; гасится с табличкой).
		fill.Offset = Vector2.new(-0.35, 0)
		local shimmer = tween(
			fill,
			TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Offset = Vector2.new(0.35, 0) }
		)
		table.insert(stops, function()
			shimmer:Cancel()
		end)
	end
end

-- Столб света над рыбаком (легендарная и мифическая рыба): неоновая сердцевина выстреливает
-- вверх на Fx.PillarHeight[редкость], вокруг — лучи (Beam) лицом к камере: свечение тает к небу
-- (без «крышки»), искры бегут вверх; всё гаснет за Fx.PillarTime[редкость]. Мифическая — выше,
-- шире и переливается. Его видно и издалека — он один на весь эффект и дешёвый (без частиц).
-- base — низ столба (земля под рыбаком; у самого рыбака — над его рыбой, чтобы не закрыть её);
-- lifeOverride — своё время жизни (короткий столб трофея после карточки, ReplayOwnTrophy).
-- Свой столб начинается в ~12 studs перед камерой: его лучи в OWN_PILLAR_WIDTH раз уже, иначе
-- свечение затянуло бы пол-экрана; чужой виден через всю лагуну — в полную ширину, а дальше
-- PILLAR_FAR studs ещё шире (на экране не тоньше ~28 px), и живёт он Fx.PillarTimeOther.
local function pillar(tracker: Tracker, base: Vector3, rarity: string, lifeOverride: number?)
	local parent = folder
	local style = UIConfig.Rarity[rarity]
	if not parent or not style then
		return
	end
	local own = isOwn(tracker)
	local life = lifeOverride
		or if own
			then Fx.PillarTime[rarity] or Fx.PillarTime.Legendary
			else Fx.PillarTimeOther[rarity] or Fx.PillarTimeOther.Legendary
	local tall = Fx.PillarHeight[rarity] or Fx.PillarHeight.Legendary
	local wide = (if style.Rainbow then 1.5 else 1) * (if own then OWN_PILLAR_WIDTH else 1)
	-- Чужой столб издалека шире (не уже ~25 px с соседнего пирса, ≈240 studs, и через лагуну) и
	-- выше: луч в небо, а не «факел» над крышами.
	local viewer = if own then nil else viewerPosition()
	local distance = if viewer then (base - viewer).Magnitude else 0
	local far = math.max(1, distance / PILLAR_FAR)
	wide *= far
	if viewer then
		tall = math.max(tall, PILLAR_SKY.base + distance * PILLAR_SKY.slope)
	end
	local fadeFrom = if own then 0.3 else PILLAR_FADE_OTHER
	local upright = CFrame.Angles(0, 0, math.pi / 2) -- ось цилиндра (X) — вертикально
	local coreWidth0 = (if own then FX.OwnPillarCore else PILLAR_CORE) * far
	local core = quietPart("PillarCore", Vector3.new(1, coreWidth0, coreWidth0), CFrame.new(base) * upright)
	core.Shape = Enum.PartType.Cylinder
	core.Material = Enum.Material.Neon
	core.Color = WHITE
	local host, bottom, top = beamHost("PillarGlow", base)
	local glow = makeBeam("Glow", host, bottom, top)
	glow.Width0 = 8 * wide
	glow.Width1 = 4 * wide
	glow.LightEmission = 1
	glow.Color = gradient({ style.Top, style.Top:Lerp(style.Bottom, 0.45), style.Bottom })
	local sparkle = makeBeam("Sparkle", host, bottom, top)
	sparkle.Width0 = 5 * wide
	sparkle.Width1 = 5 * wide
	sparkle.LightEmission = 1
	sparkle.Texture = SPARKLE_TEXTURE
	sparkle.TextureMode = Enum.TextureMode.Wrap
	sparkle.TextureLength = 5
	sparkle.TextureSpeed = 1.2
	sparkle.Color = stripes(style.Rays)
	local effect = newEffect(tracker, nil)
	table.insert(effect.instances, core)
	table.insert(effect.instances, host)
	local sound = makeSound(core, "Ping", SOUND_PING, 0.6)
	core.Parent = parent
	host.Parent = parent
	play(sound, 0.75)
	local start = os.clock()
	runEveryFrame(effect, function(now: number): boolean
		local a = (now - start) / life
		if a >= 1 then
			return false
		end
		local grow = 1 - (1 - math.min(a / 0.14, 1)) ^ 3
		local height = math.max(tall * grow, 0.5)
		local fade = math.clamp((a - fadeFrom) / (1 - fadeFrom), 0, 1)
		local coreWidth = coreWidth0 * (1 - 0.6 * fade)
		core.CFrame = CFrame.new(base + Vector3.new(0, height / 2, 0)) * upright
		core.Size = Vector3.new(height, coreWidth, coreWidth)
		core.Transparency = 0.05 + 0.95 * fade ^ 1.5
		top.Position = Vector3.new(0, height, 0)
		glow.Transparency = numbers({ { 0, 0.45 + 0.55 * fade }, { 0.7, 0.65 + 0.35 * fade }, { 1, 1 } })
		sparkle.Transparency = numbers({ { 0, 0.15 + 0.85 * fade }, { 0.8, 0.45 + 0.55 * fade }, { 1, 1 } })
		if style.Rainbow then
			local hue = (now * 0.8) % 1
			glow.Color = ColorSequence.new(Color3.fromHSV(hue, 0.6, 1), Color3.fromHSV((hue + 0.35) % 1, 0.75, 1))
		end
		return true
	end)
end

-- Разноцветные конфетти над рыбаком (одним всплеском одного ParticleEmitter'а): летят вверх
-- и в стороны и медленно планируют вниз — в кадре камеры за спиной.
local function confetti(tracker: Tracker, position: Vector3, rarity: string)
	local parent = folder
	local style = UIConfig.Rarity[rarity]
	if not parent or not style then
		return
	end
	makeRoom(tracker, 1)
	local effect = newEffect(tracker, 3.2)
	effect.priority = 2
	local part = quietPart("Confetti", Vector3.new(1, 1, 1), CFrame.new(position))
	part.Transparency = 1
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Confetti"
	emitter.Enabled = false
	emitter.Rate = 0
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.SpreadAngle = Vector2.new(70, 70)
	emitter.Speed = NumberRange.new(14, 22)
	emitter.Drag = 3
	emitter.Acceleration = Vector3.new(0, -10, 0)
	emitter.Lifetime = NumberRange.new(2.2, 3)
	emitter.Size = numbers({ { 0, 0.7 }, { 1, 0.5 } })
	emitter.Transparency = numbers({ { 0, 0 }, { 0.8, 0 }, { 1, 1 } })
	emitter.Squash = numbers({ { 0, 0 }, { 0.25, 1.2 }, { 0.5, -1.2 }, { 0.75, 1.2 }, { 1, 0 } }) -- кружатся
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-420, 420)
	emitter.Color = stripes(style.Confetti)
	emitter.LightEmission = 0.6
	emitter.LightInfluence = 0
	emitter.Texture = SPARKLE_TEXTURE
	emitter.Parent = part
	part.Parent = parent
	effect.emitter = emitter
	table.insert(effect.instances, part)
	burst(emitter, Fx.ConfettiCount)
end

-- Земля (настил пирса) под ногами рыбака: самая высокая точка из 5 лучей вниз (под ногами
-- и вокруг) мимо персонажа и эффектов — волна по земле не уходит под неровные доски. Перила
-- и ящики рядом (выше ног больше чем на GroundBump) не в счёт.
local function groundUnder(character: Model, root: BasePart): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { character }
	if folder then
		table.insert(ignore, folder)
	end
	params.FilterDescendantsInstances = ignore
	local down = Vector3.new(0, -(FEET + 4), 0)
	local under = Workspace:Raycast(root.Position, down, params)
	local feet = if under then under.Position else root.Position - Vector3.new(0, FEET, 0)
	local top = feet.Y
	local r = FX.GroundProbe
	for _, offset in { Vector3.new(r, 0, 0), Vector3.new(-r, 0, 0), Vector3.new(0, 0, r), Vector3.new(0, 0, -r) } do
		local hit = Workspace:Raycast(root.Position + offset, down, params)
		if hit and hit.Position.Y > top and hit.Position.Y <= feet.Y + FX.GroundBump then
			top = hit.Position.Y
		end
	end
	return Vector3.new(feet.X, top, feet.Z)
end

-- Рыба над головой живёт (FishLife): эффект рыбака с покадровым шагом — вблизи (FX.LifeNear)
-- гнётся, дальше (до FX.LifeRange) качается целиком через кадр, ещё дальше — в покое: эффект
-- кончается (всё возвращено), а таймер раз в FX.LifePoll с проверяет, не подошли ли ближе.
local startLife: (tracker: Tracker, held: Model) -> ()

local function pollLife(tracker: Tracker, held: Model)
	cancelThread(tracker.lifePoll)
	tracker.lifePoll = task.delay(FX.LifePoll, function()
		tracker.lifePoll = nil
		if held.Parent and trackers[tracker.player] == tracker then
			startLife(tracker, held)
		end
	end)
end

startLife = function(tracker: Tracker, held: Model)
	local current = tracker.life
	if current then
		if current.held == held and not current.effect.done then
			return
		end
		endEffect(current.effect)
	end
	local rarity = held:GetAttribute("Rarity")
	local life = FishLife.hold(held, tracker.player.UserId, if typeof(rarity) == "string" then rarity else nil)
	local head = life and life.weld.Part0
	if not life or not head then
		return
	end
	local function distance(): number
		local viewer = viewerPosition()
		return if viewer then (viewer - head.Position).Magnitude else 0
	end
	if distance() > FX.LifeRange then
		pollLife(tracker, held)
		return
	end
	cancelThread(tracker.lifePoll)
	tracker.lifePoll = nil
	local effect = newEffect(tracker, nil)
	local entry = { held = held, life = life, effect = effect }
	tracker.life = entry
	-- табличка уже над рыбой (жизнь началась позже) — тоже не трясётся
	local body = held.PrimaryPart
	for other in tracker.effects do
		for _, instance in other.instances do
			if instance.Name == "Nameplate" and instance:IsA("BillboardGui") and instance.Adornee == body then
				FishLife.plate(life, instance)
			end
		end
	end
	effect.onEnd = function()
		FishLife.release(life)
		if tracker.life == entry then
			tracker.life = nil
		end
	end
	local frame = 0
	runEveryFrame(effect, function(now: number): boolean
		if held.Parent == nil or trackers[tracker.player] ~= tracker then
			return false
		end
		local away = distance()
		if away > FX.LifeRange then
			pollLife(tracker, held) -- ушли далеко: в покой, вернёмся, если подойдут
			return false
		end
		frame += 1
		if away <= FX.LifeNear then
			FishLife.step(life, now, 2)
		elseif frame % 2 == 0 then
			FishLife.step(life, now, 1)
		end
		return true
	end)
end

-- Рыба долетела: вспышка и ореол вокруг неё, табличка, искры (редкая и выше, мутация), а у
-- легендарной и мифической — столб света (виден всем), конфетти и волна по земле (вблизи).
local function celebrate(tracker: Tracker, event: FxEvent, held: Model?, near: boolean)
	if trackers[tracker.player] ~= tracker then
		return -- рыбак ушёл
	end
	local rarity = event.rarity
	local style = UIConfig.Rarity[rarity] or UIConfig.Rarity.Common
	local character = tracker.player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local head = character and character:FindFirstChild("Head")
	local body = held and held.PrimaryPart
	if near and held and body then
		local box, size = held:GetBoundingBox()
		-- чёткий удар в точке рыбы: белый шар, «звезда» тонких лучей, тонкое кольцо
		popBall(tracker, box.Position, WHITE)
		starBurst(tracker, body, box.Position, size, rarity)
		halo(tracker, body, box.Position, style.Bottom)
		startLife(tracker, held) -- рыба над головой ожила (FishLife)
		local chime = newEffect(tracker, 1.5)
		local sound = makeSound(body, "LandPing", SOUND_PING, 0.45, isOwn(tracker))
		table.insert(chime.instances, sound)
		play(sound, if style.Flash then 0.8 else 1.2)
		aura(tracker, held, rarity, event.mutation)
		nameplate(tracker, held, rarity, event)
	end
	if style.Flash and character and root and root:IsA("BasePart") then
		local feet = groundUnder(character, root)
		local base = feet
		if held and isOwn(tracker) then
			-- Своему рыбаку столб не закрывает его самого и рыбу: начинается над рыбой.
			local box, size = held:GetBoundingBox()
			base = box.Position + Vector3.new(0, size.Y / 2 + 0.5, 0)
		elseif held and near then
			-- Чужой вблизи: над его табличкой (она над рыбой; studs + пиксели — на этом расстоянии
			-- столько studs) — неоновая сердцевина не режет рыбу и надпись. Издалека таблички нет —
			-- столб от земли.
			local box, size = held:GetBoundingBox()
			local camera = Workspace.CurrentCamera
			local plate = NAMEPLATE_STUDS.Y
			if camera and camera.ViewportSize.Y > 1 then
				local away = math.max((box.Position - camera.CFrame.Position).Magnitude, 1)
				local perStud = camera.ViewportSize.Y / (2 * away * math.tan(math.rad(camera.FieldOfView) / 2))
				plate += NAMEPLATE_PIXELS.Y / math.max(perStud, 1e-3)
			end
			base = box.Position + Vector3.new(0, size.Y / 2 + 0.4 + plate + 0.5, 0)
		end
		if isOwn(tracker) then
			-- Свой столб — когда удар уже прошёл (в кадр приземления — только рыба и удар).
			local waiting = newEffect(tracker, nil)
			waiting.thread = task.delay(FX.OwnPillarDelay, function()
				waiting.thread = nil
				endEffect(waiting)
				pillar(tracker, base, rarity)
			end)
		else
			pillar(tracker, base, rarity)
		end
		if not isOwn(tracker) then
			-- Чужой улов: HUD покажет, в какой стороне столб, если его не видно (NotifyController).
			FishingFxController.OtherTrophy:Fire(tracker.player, feet, rarity)
		end
		if near then
			-- Волна по земле: два кольца цвета редкости (мифическая — радужные пары).
			local colorPairs = if style.Rainbow
				then { { UIConfig.Rainbow[1], UIConfig.Rainbow[3] }, { UIConfig.Rainbow[5], UIConfig.Rainbow[7] } }
				else { { style.Top, style.Bottom }, { style.Bottom, style.Top } }
			for index, pair in colorPairs do
				local shockwave: RingLook = {
					from = 2,
					to = 24 - 4 * (index - 1),
					time = 0.8,
					color = pair[1],
					inner = pair[2],
					width = 0.6,
					foam = index == 1,
				}
				local delay = if index == 1 then nil else 0.16
				ringBurst(tracker, nil, feet + Vector3.new(0, FX.GroundLift, 0), shockwave, 1, 0, delay)
			end
			if head and head:IsA("BasePart") then
				confetti(tracker, head.Position + Vector3.new(0, 3, 0), rarity)
			end
		end
	end
end

-- Сдвиг прыжка к концу (u — доля времени): зависание на вершине дуги.
local function hang(u: number): number
	return u + 0.5 * math.sin(2 * math.pi * u) / (2 * math.pi)
end

-- Рыба «плюхается» над головой: в последние 0,1 с прыжка раздувается до 1,15 и сжимается
-- (множитель к её размеру).
local function landingSquash(u: number): number
	if u >= 1 or u < 0.82 then
		return 1
	elseif u < 0.9 then
		local k = (u - 0.82) / 0.08
		return 1 + 0.15 * k * k * (3 - 2 * k)
	end
	return 1.15 - 0.15 * (u - 0.9) / 0.1
end

-- Поймал: рыба выпрыгивает у поплавка и кувыркаясь летит над голову рыбака (см. шапку).
local function startLeap(tracker: Tracker, event: FxEvent)
	local player = tracker.player
	local own = isOwn(tracker)
	local rarity = event.rarity
	local landedSignal = false
	-- OwnFishLanded: ровно один раз на свой улов.
	local function land(position: Vector3)
		if own and not landedSignal then
			landedSignal = true
			FishingFxController.OwnFishLanded:Fire(rarity, position)
		end
	end
	local character = player.Character
	local headInstance = character and character:FindFirstChild("Head")
	local water = waterOrigin(tracker)
	if not character or not headInstance or not headInstance:IsA("BasePart") or not water then
		if own then
			task.defer(land, ownHeadPoint())
		end
		return
	end
	local head: BasePart = headInstance
	local near = isNear(water) or isNear(head.Position)
	local template = if near then fishTemplate(event.id, event.mutation) else nil
	if not template then
		-- Далеко (или нет модели): без прыжка, а столб света — когда рыба долетела бы.
		local waiting = newEffect(tracker, nil)
		waiting.thread = task.delay(FishingConfig.LeapTime, function()
			waiting.thread = nil
			endEffect(waiting)
			celebrate(tracker, event, nil, false)
		end)
		if own then
			task.defer(land, ownHeadPoint())
		end
		return
	end

	-- Всплеск, столб воды и круги там, где рыба выходит из воды (поплавок ещё здесь).
	local bobber = tracker.bobber
	local colors = rarityColors(rarity)
	if bobber then
		splash(bobber, SPLASH.catch, 1.6)
		play(bobber.splashSound, 0.9)
	end
	local lift = Vector3.new(0, FX.RingLift, 0)
	local catchRing = table.clone(RING.landing)
	catchRing.to = 13
	catchRing.width = 0.6
	catchRing.inner = colors[#colors]
	ringBurst(tracker, nil, water + lift, catchRing, 3, 0.12)
	spout(tracker, water, 7)
	if rarity == "Mythic" then
		-- Мифическая: ещё и радужная волна по воде.
		local hues = UIConfig.Rainbow
		for index, pair in { { hues[1], hues[3] }, { hues[4], hues[6] }, { hues[5], hues[7] } } do
			local wave: RingLook =
				{ from = 2, to = 20 - 3 * (index - 1), time = 0.9, color = pair[1], inner = pair[2], width = 0.6 }
			ringBurst(tracker, nil, water + lift, wave, 1, 0, 0.1 + 0.12 * (index - 1))
		end
	end

	makeRoom(tracker, 1)
	local model = cloneFish(template, "Leap")
	local body = model.PrimaryPart :: BasePart
	local flex = FishLife.leap(model) -- рыба гнётся в прыжке (хвост бьёт), к концу затихает
	local center, size = fishBox(model)
	-- Рыба растёт в полёте: из воды — крупнее настоящей (LEAP_START доля пути к размеру над
	-- головой), к LEAP_GROWN прыжка — как над головой (FishingConfig.HeldScale) и «плюхается»
	-- (landingSquash).
	local target = heldScale(rarity, size)
	local modelInHead = heldPlacement(head, center, size, target)
	local effect = newEffect(tracker, nil)
	effect.priority = 3
	effect.tag = "leap"
	table.insert(effect.instances, model)
	-- След вдоль оси вращения (поперёк рыбы) — лента не перекручивается, пока рыба кувыркается.
	local centerInBody = body.CFrame:PointToObjectSpace(model:GetPivot() * center)
	local half = math.max(size.Z, 1) * 0.5 + 0.2
	makeTrails(body, centerInBody + Vector3.new(0, 0, half), centerInBody - Vector3.new(0, 0, half), colors, "Leap")
	local emitter = sparkleEmitter("LeapSparkles", colors, 40)
	emitter.Parent = body
	effect.emitter = emitter
	local whoosh = makeSound(body, "Whoosh", SOUND_WHOOSH, 0.4, own)

	-- Дуга: центр рамки рыбы от воды (нос чуть над водой) до места над головой.
	local mouth = center + Vector3.new(size.X / 2, 0, 0) -- голова рыбы (+X модели): тут крючок
	local startCenter = water - Vector3.new(0, size.X * 0.3, 0)
	local firstEnd = (head.CFrame * modelInHead) * (center * target)
	local height = math.clamp((firstEnd - startCenter).Magnitude * Fx.LeapHeight, Fx.LeapMinHeight, Fx.LeapMaxHeight)
	-- Дуга выгнута вправо от камеры смотрящего (насколько камера смотрит вдоль прыжка):
	-- из-за спины рыбака прыжок читается кривой, а не точкой, летящей в объектив.
	local bow = Vector3.zero
	local camera = Workspace.CurrentCamera
	local path = flat(firstEnd - startCenter)
	if camera and path.Magnitude > 0.01 then
		local along = path.Unit
		local right = flat(camera.CFrame.RightVector)
		bow = (right - along * right:Dot(along)) * Fx.LeapBow
	end
	-- Кувырки вокруг оси Z модели; в начале нос смотрит вверх (+X → +Y), к доле LeapSpinEnd
	-- полёта рыба уже повёрнута как над головой.
	local spin = Fx.LeapSpins * 2 * math.pi + math.pi / 2
	local start = os.clock()
	local oldHeld = character:FindFirstChild("HeldFish")
	local hidden: Model? = nil
	local landedAt: number? = nil
	local scale = 1
	local function leapScale(u: number): number
		local from = 1 + (target - 1) * LEAP_START
		local grow = math.clamp((u - 0.1) / (LEAP_GROWN - 0.1), 0, 1)
		return (from + (target - from) * grow * grow * (3 - 2 * grow)) * landingSquash(u)
	end
	local lastCenter = startCenter
	-- Капли воды с рыбы: пачка при выходе из воды, потом по паре, пока она поднимается.
	local drips = FishLife.drips(folder :: Instance, water.Y)
	local lastStep, nextDrip = start, start
	local function drip(now: number, count: number, velocity: Vector3)
		for _ = 1, count do
			local offset = Vector3.new(rng:NextNumber(-0.45, 0.45) * size.X, rng:NextNumber(-0.5, 0) * size.Y, 0)
			local spread = Vector3.new(rng:NextNumber(-2.5, 2.5), rng:NextNumber(0, 3), rng:NextNumber(-2.5, 2.5))
			local part = FishLife.drip(drips, lastCenter + offset, velocity * 0.35 + spread, now)
			if part then
				table.insert(effect.instances, part)
			end
		end
	end

	local function pose(u: number): CFrame
		local a = hang(u)
		local endPivot = head.CFrame * modelInHead
		local position = startCenter:Lerp(endPivot * (center * target), a)
			+ Vector3.new(0, height * 4 * a * (1 - a), 0)
			+ bow * math.sin(math.pi * a)
		local turn = spin * (1 - math.min(u / Fx.LeapSpinEnd, 1)) ^ 2
		lastCenter = position
		return CFrame.new(position) * endPivot.Rotation * CFrame.Angles(0, 0, turn) * CFrame.new(-center * scale)
	end

	-- Поплавок на крючке летит с рыбой; не долетит — сматывается как обычно.
	if bobber then
		bobber.hooked = effect
		bobber.retractFrom = nil
		bobber.alert.gui.Enabled = false
		bobber.wake.Enabled = false
		setGlowFill(bobber, nil)
		FishingLine.reset(bobber.line) -- леска прямая: рыба тянет поплавок за собой
		bobber.shadowGone = "caught"
		local shadow = bobber.shadow
		if shadow then
			FishShadow.destroy(shadow) -- тень была рыбой — теперь она в прыжке
			bobber.shadow = nil
		end
		fadeOwned(tracker, bobber)
	end
	effect.onEnd = function()
		local shown = hidden
		if shown then
			setHidden(shown, false)
		end
		if bobber and bobber.hooked == effect and tracker.bobber == bobber then
			destroyBobber(tracker)
		end
		land(lastCenter) -- прыжок оборвался (рыбак умер или ушёл): сигнал всё равно один раз
		if own then
			task.defer(updateCamera)
		end
	end

	scale = leapScale(0)
	pcall(function()
		model:ScaleTo(scale)
	end)
	model:PivotTo(pose(0))
	model.Parent = folder
	play(whoosh, 1.15)

	runEveryFrame(effect, function(now: number): boolean
		if not head:IsDescendantOf(Workspace) then
			return false -- рыбак умер или ушёл: прыжок обрывается
		end
		local u = math.min((now - start) / FishingConfig.LeapTime, 1)
		local held = character:FindFirstChild("HeldFish")
		local fresh: Model? = if held and held ~= oldHeld and held:IsA("Model") then held else nil
		local exact = fresh and fresh:GetAttribute("Scale")
		if typeof(exact) == "number" and exact > 0 and math.abs(exact - target) > 1e-3 then
			target = exact -- сервер повесит рыбу такого размера: к нему и растём
			modelInHead = heldPlacement(head, center, size, target)
		end
		local wanted = if u >= 1 then target else leapScale(u)
		-- (в полёте — шагами по 2 %, «плюх» и приземление — точно)
		if math.abs(wanted - scale) > (if u >= 0.8 then 1e-3 else 0.02) then
			scale = wanted
			pcall(function()
				model:ScaleTo(scale)
			end)
		end
		local previous = lastCenter
		local cframe = pose(u)
		if flex then
			FishLife.leapPose(flex, cframe, u, now, scale)
		else
			model:PivotTo(cframe)
		end
		local dt = math.max(now - lastStep, 1 / 240)
		lastStep = now
		if u < 0.42 and now >= nextDrip then
			drip(now, if nextDrip == start then 5 else 2, (lastCenter - previous) / dt)
			nextDrip = now + 0.1
		end
		FishLife.stepDrips(drips, now, dt)
		if bobber and bobber.hooked == effect then
			bobber.position = cframe * (mouth * scale)
			bobber.model:PivotTo(CFrame.new(bobber.position))
		end
		if u < 1 then
			if fresh and not hidden then
				hidden = fresh -- серверная рыба пришла раньше — прячем до конца прыжка
				setHidden(fresh, true)
			end
			return true
		end
		if not landedAt then
			landedAt = now
			land(cframe * (center * scale)) -- своя рыба долетела: в этот кадр — OwnFishLanded
		end
		if fresh or now - (landedAt :: number) >= Fx.HandoffWait then
			endEffect(effect) -- копия исчезает, серверная рыба (если спрятана) показывается
			celebrate(tracker, event, fresh, true)
			return false
		end
		return true
	end)
end

-- Рыба ушла: леска вспыхивает, поплавок подскакивает, всплеск, круги и рыбка, махнув
-- хвостом, ныряет прочь от рыбака.
local function startDive(tracker: Tracker, event: FxEvent)
	local bobber = tracker.bobber
	if bobber and not bobber.hooked and not bobber.retractFrom then
		FishingLine.flash(bobber.line, os.clock())
		bobber.shadowGone = "lost"
		if bobber.landed then
			bobber.popStart = os.clock()
			bobber.alert.gui.Enabled = false
			bobber.wake.Enabled = false
			setGlowFill(bobber, nil)
		end
	end
	local water = waterOrigin(tracker)
	if not water or not isNear(water) then
		return
	end
	if bobber then
		splash(bobber, SPLASH.lost, 1.1)
		play(bobber.splashSound, 1.2)
	end
	ringBurst(tracker, nil, water + Vector3.new(0, FX.RingLift, 0), RING.lost, 2, 0.15)
	spout(tracker, water, 3.5)

	local template = fishTemplate(event.id or FALLBACK_FISH, event.mutation) or fishTemplate(FALLBACK_FISH, nil)
	local parent = folder
	if not template or not parent then
		return
	end
	local model = cloneFish(template, "Dive")
	if Fx.DiveScale ~= 1 then
		pcall(function()
			model:ScaleTo(Fx.DiveScale)
		end)
	end
	local pivot = model:GetPivot()
	local box = model:GetBoundingBox()
	local center = pivot:PointToObjectSpace(box.Position)
	local character = tracker.player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local away = if root and root:IsA("BasePart") then flat(water - root.Position) else Vector3.xAxis
	away = if away.Magnitude > 0.01 then away.Unit else Vector3.xAxis

	-- Прыжок-дуга: из-под воды на 2,5 stud над ней и вниз, на 4,6 stud под воду.
	local run, rise, sink = 4, 14.9, 19.1
	local effect = newEffect(tracker, nil)
	table.insert(effect.instances, model)
	local start = os.clock()
	local splashed = false
	local function place(a: number)
		local y = -0.4 + rise * a - sink * a * a
		local position = water + away * (run * a) + Vector3.new(0, y, 0)
		local forward = (away * run + Vector3.new(0, rise - 2 * sink * a, 0)).Unit
		local facing = CFrame.lookAt(position, position + forward) * CFrame.Angles(0, math.pi / 2, 0)
		local flick = CFrame.Angles(0, math.sin(a * 6 * math.pi) * 0.45, 0) -- машет хвостом
		model:PivotTo(CFrame.new(position) * facing.Rotation * flick * CFrame.new(-center))
		if not splashed and a > 0.5 and y < 0 then
			splashed = true -- вошла в воду: маленький круг
			local small = table.clone(RING.reel)
			small.to = 3.5
			ringBurst(tracker, nil, Vector3.new(position.X, water.Y + FX.RingLift, position.Z), small, 1, 0)
		end
	end
	place(0)
	model.Parent = parent
	runEveryFrame(effect, function(now: number): boolean
		local a = (now - start) / Fx.DiveTime
		if a >= 1 then
			return false
		end
		place(a)
		return true
	end)
end

-- "<номер>|caught|<FishId>|<Mutation>|<Rarity>" / "<номер>|lost|…" (см. RemoteNames).
local function parseFx(value: any): FxEvent?
	if typeof(value) ~= "string" then
		return nil
	end
	local fields = string.split(value, "|")
	local kind = fields[2]
	if kind ~= "caught" and kind ~= "lost" then
		return nil
	end
	local function field(index: number): string?
		local text = fields[index]
		return if text and text ~= "" then text else nil
	end
	local rarity = field(5)
	return {
		kind = kind,
		id = field(3),
		mutation = field(4),
		rarity = if rarity and UIConfig.Rarity[rarity] then rarity else "Common",
	}
end

local function onFxChanged(tracker: Tracker)
	local value = tracker.player:GetAttribute("FishFx")
	if value == tracker.fxEvent then
		return
	end
	tracker.fxEvent = value
	local event = parseFx(value)
	if not event then
		return
	end
	if event.kind == "caught" then
		startLeap(tracker, event)
	else
		startDive(tracker, event)
	end
end

--------------------------------------------------------------------------------
-- Игроки
--------------------------------------------------------------------------------

local function trackPlayer(player: Player)
	if trackers[player] then
		return
	end
	local tracker: Tracker = {
		player = player,
		trove = Trove.new(),
		bobber = nil,
		effects = {},
		-- Событие, которое было до нас (вошли в игру позже), не повторяем.
		fxEvent = player:GetAttribute("FishFx"),
		life = nil,
		lifePoll = nil,
		ringPool = {},
	}
	trackers[player] = tracker
	tracker.trove:Add(function()
		cancelThread(tracker.lifePoll)
		tracker.lifePoll = nil
		destroyBobber(tracker)
		for effect in table.clone(tracker.effects) do
			endEffect(effect)
		end
		for _, rig in tracker.ringPool do
			rigOf[rig.part] = nil
			rig.part:Destroy()
		end
		table.clear(tracker.ringPool)
	end)
	-- Рыба над головой появилась не из прыжка на наших глазах (вошли в игру позже, рыба пришла
	-- после передачи): она тоже живая. Свой прыжок ещё летит — жизнь начнёт celebrate.
	local charTrove = tracker.trove:Add(Trove.new())
	local function noticeHeld(child: Instance)
		if child.Name ~= "HeldFish" or not child:IsA("Model") then
			return
		end
		for effect in tracker.effects do
			if effect.tag == "leap" then
				return
			end
		end
		task.defer(function()
			if child.Parent and trackers[player] == tracker then
				startLife(tracker, child :: Model)
			end
		end)
	end
	local function watchCharacter(character: Model?)
		charTrove:Clean()
		if character then
			charTrove:Connect(character.ChildAdded, noticeHeld)
			local held = character:FindFirstChild("HeldFish")
			if held then
				noticeHeld(held)
			end
		end
	end
	tracker.trove:Connect(player.CharacterAdded, watchCharacter)
	watchCharacter(player.Character)
	tracker.trove:Connect(player:GetAttributeChangedSignal("FishingState"), function()
		onStateChanged(player, tracker)
	end)
	for _, attribute in { "BobberTarget", "CastTime" } do
		tracker.trove:Connect(player:GetAttributeChangedSignal(attribute), function()
			onCastChanged(tracker)
		end)
	end
	tracker.trove:Connect(player:GetAttributeChangedSignal("FishFx"), function()
		onFxChanged(tracker)
	end)
	onStateChanged(player, tracker)
end

local function untrackPlayer(player: Player)
	local tracker = trackers[player]
	if tracker then
		trackers[player] = nil
		tracker.trove:Clean()
	end
end

--------------------------------------------------------------------------------
-- Радужные рыбы
--------------------------------------------------------------------------------

-- Видна ли модель отсюда: в мире — не дальше Fx.Range от персонажа или камеры; в своём
-- интерфейсе (ViewportFrame карточки улова) — всегда.
local function isShown(instance: Instance): boolean
	if instance:IsDescendantOf(Workspace) then
		local at: Vector3? = nil
		if instance:IsA("Model") then
			at = instance:GetPivot().Position
		elseif instance:IsA("BasePart") then
			at = instance.Position
		end
		if not at then
			return true
		end
		local viewer = viewerPosition()
		if viewer and (viewer - at).Magnitude <= Fx.Range then
			return true
		end
		local camera = Workspace.CurrentCamera
		return camera ~= nil and (camera.CFrame.Position - at).Magnitude <= Fx.Range
	end
	return playerGui ~= nil and instance:IsDescendantOf(playerGui)
end

-- Рыба в руках персонажа (внутри модели с Humanoid — HeldFish у головы).
local function heldByCharacter(instance: Instance): boolean
	local parent = instance.Parent
	while parent and parent ~= Workspace do
		if parent:IsA("Model") and parent:FindFirstChildOfClass("Humanoid") then
			return true
		end
		parent = parent.Parent
	end
	return false
end

local function paint(entry: RainbowModel, shift: number)
	for index, part in entry.parts do
		local hue = (entry.u[index] * 0.85 + shift) % 1
		part.Color = Color3.fromHSV(hue, 0.72, 0.55 + 0.45 * entry.v[index])
	end
end

local function paintRainbows(t: number)
	for instance, entry in rainbow do
		if heldByCharacter(instance) then
			-- реже, ступенями и только вблизи: Color детали персонажа пересобирает его меш
			local at = if instance:IsA("Model") then instance:GetPivot().Position else nil
			local viewer = viewerPosition()
			if at and viewer and (viewer - at).Magnitude > FX.LifeNear then
				continue
			end
			local step = math.floor(t * 0.35 * RAINBOW_STEPS)
			if t < entry.nextPaint or step == entry.step then
				continue
			end
			entry.step = step
			entry.nextPaint = t + 1 / RAINBOW_HELD_RATE
			paint(entry, step / RAINBOW_STEPS)
		elseif isShown(instance) then
			entry.step = nil
			paint(entry, t * 0.35)
		end
	end
end

-- Heartbeat только пока есть что перекрашивать.
local function updateRainbowLoop()
	if next(rainbow) ~= nil then
		if not rainbowConnection then
			local sincePaint = 0
			rainbowConnection = RunService.Heartbeat:Connect(function(dt: number)
				sincePaint += dt
				if sincePaint >= 1 / RAINBOW_RATE then
					sincePaint = 0
					paintRainbows(os.clock())
				end
			end)
		end
	elseif rainbowConnection then
		rainbowConnection:Disconnect()
		rainbowConnection = nil
	end
end

local function addRainbow(instance: Instance)
	if rainbow[instance] or instance:IsDescendantOf(ReplicatedStorage) then
		return -- шаблоны в ReplicatedStorage не трогаем
	end
	local entry: RainbowModel = { parts = {}, u = {}, v = {}, step = nil, nextPaint = 0 }
	for _, item in instance:GetDescendants() do
		local u, v = item:GetAttribute("RainbowU"), item:GetAttribute("RainbowV")
		if item:IsA("BasePart") and typeof(u) == "number" and typeof(v) == "number" then
			table.insert(entry.parts, item)
			table.insert(entry.u, u)
			table.insert(entry.v, v)
		end
	end
	rainbow[instance] = entry
	updateRainbowLoop()
end

local function removeRainbow(instance: Instance)
	if rainbow[instance] then
		rainbow[instance] = nil
		updateRainbowLoop()
	end
end

local function startRainbows()
	CollectionService:GetInstanceAddedSignal(RAINBOW_TAG):Connect(addRainbow)
	CollectionService:GetInstanceRemovedSignal(RAINBOW_TAG):Connect(removeRainbow)
	for _, instance in CollectionService:GetTagged(RAINBOW_TAG) do
		addRainbow(instance)
	end
end

--------------------------------------------------------------------------------
-- API и запуск
--------------------------------------------------------------------------------

-- «?» над своим поплавком на «примерке» (эхо «?» над кнопкой): выскакивает, поднимается и
-- тает за NIBBLE_MARK секунд. Billboard размером как чужой «!» (studs + пиксели), сквозь стены.
local function nibbleMark(tracker: Tracker, bobber: Bobber)
	local gui = Instance.new("BillboardGui")
	gui.Name = "NibbleMark"
	gui.Adornee = bobber.root
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = Fx.Range
	gui.ClipsDescendants = false
	local px = FX.AlertOtherPixels + 14
	gui.Size = UDim2.new(FX.AlertOtherStuds, px, FX.AlertOtherStuds, px)
	gui.StudsOffset = Vector3.new(0, FX.AlertOtherLift, 0)
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "?"
	label.TextScaled = true
	label.FontFace = FONT
	label.TextColor3 = WHITE
	label.TextStrokeColor3 = INK
	label.TextStrokeTransparency = 0
	label.Rotation = -12
	local outline = Instance.new("UIStroke")
	outline.Name = "Outline"
	outline.Color = INK
	outline.Thickness = 2
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	outline.Parent = label
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = label
	label.Parent = gui
	gui.Parent = bobber.root
	local effect = newEffect(tracker, NIBBLE_MARK + 0.05, bobber)
	table.insert(effect.instances, gui)
	tween(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	tween(gui, TweenInfo.new(NIBBLE_MARK, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffset = Vector3.new(0, FX.AlertOtherLift + 1.2, 0),
	})
	local fade =
		TweenInfo.new(NIBBLE_MARK * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, NIBBLE_MARK * 0.5)
	tween(label, fade, { TextTransparency = 1, TextStrokeTransparency = 1 })
	tween(outline, fade, { Transparency = 1 })
end

-- «Примерка» рыбы на своём поплавке (только на этом клиенте, см. шапку). true — показана.
function FishingFxController.Nibble(): boolean
	local tracker = trackers[Players.LocalPlayer]
	local bobber = tracker and tracker.bobber
	if
		not tracker
		or not bobber
		or not bobber.landed
		or bobber.state ~= "Waiting"
		or bobber.retractFrom
		or bobber.hooked
		or bobber.popStart
	then
		return false
	end
	bobber.nibbleAt = os.clock()
	splash(bobber, SPLASH.nibble, 0.7)
	ringBurst(tracker, bobber, waterUnder(bobber, bobber.target) + Vector3.new(0, FX.RingLift, 0), RING.nibble, 1, 0)
	nibbleMark(tracker, bobber)
	return true
end

-- Поплавок игрока (если леска в воде или сматывается) — для других контроллеров и тестов.
function FishingFxController.GetBobber(player: Player): Model?
	local tracker = trackers[player]
	local bobber = tracker and tracker.bobber
	return bobber and bobber.model
end

-- Детали эффектов рыбака, которые сейчас в мире на этом клиенте (круги, прыжок, столбы воды
-- и света, вспышка, ореол, табличка, конфетти, искры над рыбой), без поплавка — для тестов
-- и отладки.
function FishingFxController.GetEffects(player: Player): { Instance }
	local list = {}
	local tracker = trackers[player]
	if tracker then
		for effect in tracker.effects do
			for _, instance in effect.instances do
				table.insert(list, instance)
			end
		end
	end
	return list
end

-- Сколько ParticleEmitter'ов эффектов рыбака сейчас на этом клиенте (с брызгами поплавка).
function FishingFxController.CountEmitters(player: Player): number
	local tracker = trackers[player]
	return if tracker then emitterCount(tracker) else 0
end

-- Карточка улова закрылась (FishingController — когда 🐟 летит в счётчик): свой трофей над
-- головой «вспыхивает» ещё раз — шар и ореол, табличка подпрыгивает, искры брызгают, звон; у
-- легендарной и мифической — короткий столб света над рыбой (TROPHY_PILLAR_TIME). Только на
-- этом клиенте. false — рыбы над головой уже нет (ничего).
function FishingFxController.ReplayOwnTrophy(): boolean
	local own = Players.LocalPlayer
	local tracker = trackers[own]
	local character = own.Character
	local held = character and character:FindFirstChild("HeldFish")
	local body = if held and held:IsA("Model") then held.PrimaryPart else nil
	if not tracker or not held or not held:IsA("Model") or not body then
		return false
	end
	local rarityAttr = held:GetAttribute("Rarity")
	local rarity = if typeof(rarityAttr) == "string" and UIConfig.Rarity[rarityAttr] then rarityAttr else "Common"
	local style = UIConfig.Rarity[rarity]
	local box, size = held:GetBoundingBox()
	local camera = Workspace.CurrentCamera
	local short = camera ~= nil and camera.ViewportSize.Y > 1 and camera.ViewportSize.Y < TROPHY_SHORT_SCREEN
	popBall(tracker, box.Position, WHITE)
	starBurst(tracker, body, box.Position, size, rarity)
	halo(tracker, body, box.Position, style.Bottom, if short then HALO_TO * TROPHY_SHORT_HALO else nil)
	local life = tracker.life
	if life and life.held == held then
		FishLife.kick(life.life, os.clock(), 1.4) -- рыба ещё раз бьёт хвостом вместе со вспышкой
	end
	for effect in tracker.effects do
		local emitter = effect.emitter
		if emitter and emitter.Name == "RarityAura" and emitter.Parent then
			burst(emitter, if short then 30 else 14)
		end
		for _, instance in effect.instances do
			if instance.Name == "Nameplate" and instance:IsA("BillboardGui") then
				fitOwnPlate(instance) -- (своя: у кнопок HUD — справа, слева или меньше)
			end
			if instance.Name == "Nameplate" and instance:IsA("BillboardGui") and not revealPlate(instance, 0.15) then
				-- Уже видна (карточку закрыли без «повтора», не тот экран) — подпрыгивает.
				local plate = instance:FindFirstChild("Plate")
				local scale = plate and plate:FindFirstChild("FxScale")
				if scale and scale:IsA("UIScale") then
					scale.Scale = 1.25
					tween(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
				end
			end
		end
	end
	local chime = newEffect(tracker, 1.5)
	local sound = makeSound(body, "TrophyPing", SOUND_PING, 0.4, true)
	table.insert(chime.instances, sound)
	play(sound, if style.Flash then 0.9 else 1.3)
	if style.Flash and not short then
		pillar(tracker, box.Position + Vector3.new(0, size.Y / 2 + 0.5, 0), rarity, TROPHY_PILLAR_TIME)
	end
	FishingFxController.TrophyReplayed:Fire()
	return true
end

-- Рыба над головой игрока шлёпает хвостом сейчас (FisherAnimController: «показ» трофея — рывок
-- руками в тот же кадр). false — рыба над головой сейчас не живёт (нет её / далеко).
function FishingFxController.KickHeldFish(player: Player, power: number?): boolean
	local tracker = trackers[player]
	local life = tracker and tracker.life
	if not life or life.effect.done or life.held.Parent == nil then
		return false
	end
	FishLife.kick(life.life, os.clock(), power)
	return true
end

-- Насколько поплавок игрока сейчас притоплен рыбой, 0..1: рывки поклёвки (BiteDip) и своя
-- «примерка» (Nibble). 0 — не на воде / не клюёт. Для FisherAnimController: кончик удочки
-- дёргается вместе с поплавком.
function FishingFxController.GetBobberDip(player: Player): number
	local tracker = trackers[player]
	local bobber = tracker and tracker.bobber
	return if bobber then dipOf(bobber, os.clock()) else 0
end

function FishingFxController:Start(hud: ScreenGui)
	hudGui = hud
	-- Карточка улова открылась — камера сразу «подтягивается» (FX.TrophyCamera), не ждёт проверки.
	local fishing = hud:FindFirstChild("Fishing")
	local card = fishing and fishing:FindFirstChild("CatchCard")
	if card and card:IsA("GuiObject") then
		card:GetPropertyChangedSignal("Visible"):Connect(function()
			if card.Visible then
				updateCamera()
			end
		end)
	end
	local fxFolder = Instance.new("Folder")
	fxFolder.Name = FOLDER_NAME
	fxFolder.Parent = Workspace
	folder = fxFolder
	local assets = ReplicatedStorage:WaitForChild("Assets")
	bobbersFolder = assets:WaitForChild("Bobbers")
	fishFolder = assets:WaitForChild("Fish")

	-- Своя рыба в мини-игре: её редкость (тень под поплавком крупнее у редкой — FishShadow).
	Net.Event("FishingState").OnClientEvent:Connect(function(state: any, data: any)
		local tracker = trackers[Players.LocalPlayer]
		local bobber = tracker and tracker.bobber
		if not bobber or type(data) ~= "table" then
			return
		end
		if state == "Minigame" then
			bobber.rarity = if typeof(data.Rarity) == "string" then data.Rarity else bobber.rarity
			bobber.hitsNeeded = if typeof(data.HitsNeeded) == "number" then data.HitsNeeded else nil
		elseif state == "Zone" and typeof(data.Hits) == "number" then
			-- попал: поплавок рывком подтягивается к рыбаку (reelPull)
			local now = os.clock()
			local creep = math.min(FX.ReelCreepMax, (now - bobber.stateSince) * FX.ReelCreep)
			bobber.pullFrom = reelPull(bobber, now) - creep
			bobber.hits = data.Hits
			bobber.hitAt = now
		end
	end)
	Players.PlayerAdded:Connect(trackPlayer)
	Players.PlayerRemoving:Connect(untrackPlayer)
	for _, player in Players:GetPlayers() do
		trackPlayer(player)
	end
	playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	startRainbows()
end

return FishingFxController
