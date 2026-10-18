--!strict
--[[
	FishingController — рыбалка локального игрока: кнопка действия, поклёвка, мини-игра,
	карточка улова и подсказки (Этап 2). Интерфейс — HUD.Fishing (tools/builder/gui/Fishing.luau),
	стиль «Симулятор» (UI v5: сочные кнопки и плашки с толстой обводкой в тёмный оттенок своего
	цвета, светлым ободком, обведёнными значками и «стеклянными» таблетками) и вся анимация —
	tools/builder/gui/STYLE.md §3 и ReplicatedStorage.Shared.UiFx.

	Сервер (FishingService) решает всё сам. Клиент только просит (FishingCast / FishingHook /
	FishingTap / FishingStop) и показывает то, что сервер прислал в FishingState
	(протокол — в шапке RemoteNames).

	  • Кнопка действия (ActionArea.ActionButton) видна, пока удочка в руке персонажа или в его
	    рюкзаке (тогда это «ВЗЯТЬ»): на экране всегда есть главная кнопка, не одна «ДОМОЙ». Это
	    большая круглая кнопка (значок посередине, надпись — на тёмной полупрозрачной
	    «таблетке»; якорь — в её середине, раздувается она вокруг себя и вместе с белыми кольцами
	    не ближе 16 px к кнопке прыжка: атрибут GrowMax, layoutColumn — на планшете она для этого
	    чуть меньше); цвет, значок и надпись — по состоянию: «ЗАБРОСИТЬ» (Sky 🎣,
	    единственная «живая» кнопка в покое: дышит, блестит, раз в ≈ 3 с качает значком; пока за
	    сессию не было заброса — на её левом плече качается красный кружок «!», как у кнопок
	    образца) → «ЖДИ КЛЁВА…» (v3: Pond — приглушённая бирюза, кнопка меньше на 15 % и чуть
	    покачивается: жать не нужно; поплавок покачивается, точки
	    бегут, рыба 1–2 раза «пробует» наживку — кнопка вздрагивает, всплывает «?», поплавок в
	    мире притапливается; в самое первое ожидание за игру — подсказка «Жди, пока клюнет —
	    потом жми!») → «ПОДСЕЧЬ!» (Sun,
	    знак «!», пульсирует и светится кольцами в такт поклёвке) → «ЛОВИ!» (Leaf 🎯). «ЖДЁМ…» на
	    Slate ⏳ (песочные часы переворачиваются; нажатия не работают) — пока сервер отвечает на
	    заброс, после подсечки и CastCooldown секунд после конца рыбалки. С удочкой, но далеко
	    от точки рыбалки — «КУДА ИДТИ?» (Slate 🧭): нажатие не забрасывает и не ругает, а показывает
	    дорогу (спокойная подсказка 💡, компас делает оборот, луч к точке вспыхивает; идёт игрок
	    сам). Удочка в рюкзаке — «ВЗЯТЬ» где угодно (есть база, персонаж жив; Gold 🎣, зовёт
	    белыми кольцами, новичку — красный «!»): берёт удочку в руку, дальше — «ЗАБРОСИТЬ» у
	    точки или «КУДА ИДТИ?» вдали; после возрождения и «ДОМОЙ» — снова она. Пока идёт улов,
	    кнопка «замирает» (тусклое «ЖДЁМ…»: нажатия долей не пропускают — это делает только тап
	    по карточке), а когда карточка показана целиком — «ЗАБРАТЬ!» (Leaf 👍, белые кольца:
	    нажатие закрывает карточку, как и «Тапни — забрать!»; но не «по инерции» — не раньше
	    CARD.Mash секунд после прошлого нажатия). Смена
	    состояния — цвета и обводка перетекают (UiFx.recolor), кнопка «ударяет», значок влетает с
	    оборотом, надпись «ударяет» (на «ПОДСЕЧЬ!», «ЛОВИ!», «ЗАБРАТЬ!» ещё и белая вспышка
	    «превращения» — UiFx.morphFlash); нажатие — кнопка сжимается, темнеет и с перелётом
	    пружинит, значок «пинается» (UiFx.press), от касания — рябь.
	    То же действие — тап/клик удочкой по миру (Tool.Activated; на тач-экране — не в
	    мини-игре, не на экране улова и не с «КУДА ИДТИ?»: туда попадают и движения камеры и
	    джойстика) и клавиша F / R2 на геймпаде
	    (ContextActionService, только пока удочка в руке; не E — E нужна ProximityPrompt).
	    «ВЗЯТЬ» жмут и клавиши 1, F, R2 — как прежняя панель предметов (своё действие TAKE_ACTION,
	    только пока «ВЗЯТЬ» на кнопке); 1 с удочкой в руке в покое убирает её в рюкзак (не посреди
	    рыбалки и не на экране улова) — кнопка снова «ВЗЯТЬ».
	    Без тач-экрана клавиша нарисована на плече кнопки — «клавиша» KeyChip («F» / «R2»).
	  • В мини-игре нажатие засчитывается в момент касания кнопки (MouseButton1Down), а не
	    отпускания (двойной тап по «ПОДСЕЧЬ!» сервер не считает промахом — FishingConfig.HookTapGrace).
	    На тач-экране так же считается касание самой панели мини-игры (Minigame.TapPad).
	  • «СМОТАТЬ» (StopButton, красная кнопка с 🎣 слева — «смотать удочку») — пока леска в воде и
	    рыбы на крючке нет: в поклёвку и мини-игру её нет (тап мимо «ПОДСЕЧЬ!» / «ЛОВИ!» не стоит
	    рыбы). Выскакивает из своего правого нижнего угла (якорь там): к «ДОМОЙ» не растёт.
	  • Поклёвка (BiteAlert): «КЛЮЁТ!» выпрыгивает из своего поплавка и летит на своё место
	    (v3: не «удар» на весь экран поверх рыбака; если по пути заслонила бы рыбака — «выскакивает»
	    на месте; поплавка не видно — на телефоне «выскакивает», на планшете и ПК «ударяет» сверху,
	    но не крупнее, чем позволяют 16 px до ленты кнопки действия на пике её «удара», джойстика и
	    рыбака — slamRoom, иначе тоже «выскакивает»), солнечная вспышка, камера на миг
	    «приближается» (UiFx.fovPunch), края экрана светятся солнцем; всё дальше — в одном такте
	    BITE_BEAT: плашка и кнопка пульсируют вместе, кольцо от кнопки на каждый такт, знаки «!»
	    по краям качаются по очереди, «КЛЮЁТ!» вспыхивает золотом; к концу окна такт ускоряется и
	    плашку потряхивает. Полоска времени тает за Window секунд (зелёная → жёлтая → красная), то
	    же время убывает кольцом-таймером по краю кнопки (внутри её тёмной обводки, на тёмной
	    канавке), за плашкой — спокойные лучи. Плашка уходит копией: подсекли — «вдох» и белое
	    кольцо (под мини-игрой), не успели — сползает вниз и тает. На тач-экране тап по самой плашке
	    — подсечка (BiteAlert.TapPad); новичку (первые поклёвки за игру) 👇 сверху
	    показывает на кнопку. Ни свой поплавок, ни свой рыбак не прячутся под плашкой: если нырок
	    поплавка или рыбак (FishingLayout.fisherBox) попадает на неё, плашка становится чуть ниже
	    или отъезжает вбок (keepClearOfBobber); на телефоне она стоит под ногами рыбака, а если
	    камера рыбалки опустила его к самому низу кадра — слева от него (где потом мини-игра).
	  • Мини-игра (Minigame): стрелка = FishingRules.Needle(U0, Speed, t), где t — сколько секунд
	    прошло с получения "Minigame" (os.clock). Нажатие отправляет серверу это же t, а сервер
	    проверяет попадание по той же формуле — игрок видит ровно то, что проверяет сервер (и
	    зона по ширине всегда нарисована ровно такой, какой её проверяет сервер: «выскакивает»
	    она только по высоте). Заголовок — белый в цвет редкости (мифическая — бегущая радуга),
	    у стрелки — головка ▼ и шлейф — четыре белые с голубым отливом копии вплотную (ПОД зоной,
	    всё прозрачнее и уже к хвосту), на зоне едет 🐟
	    (под стрелкой; кто на крючке — по редкости: 🐟 🐠 🐡 🦈 🐉, у легендарной и мифической —
	    крупнее и светится), зона мягко «дышит» светом. Редкая — лёгкая обводка панели;
	    эпическая и выше — обводка в цвет редкости, лучи за панелью и цветные края экрана;
	    легендарная и мифическая — ещё «удар» заголовка со вспышкой, огромное слово редкости над
	    панелью (один раз; первое же слово попадания, промаха или победы его сбивает — два слова
	    в одной полосе не складываются; на телефоне оно пониже и на плашку базы и её флажок не
	    залезает) и стук сердца. На телефоне (HUD ниже 500 px) панель встаёт СЛЕВА от своего
	    рыбака (keepClearOfBobber с dock: под плашкой базы, над джойстиком) — видно всю борьбу
	    (упор, катушку, согнутую удочку) и поплавок; на планшете и ПК — внизу по центру, а если там
	    она легла бы на рыбака (камера рыбалки опускает его к низу кадра), — тоже слева, целиком
	    меньше (или сбоку внизу). Слова над панелью (редкость, попадания, «МИМО!») — не на своём
	    рыбаке (в сторону от него) и не на плашках статуса; «удар» с большого растёт от края,
	    дальнего от рыбака (FishingLayout.slamPivot). Новичку (первые мини-игры за игру) 👇
	    показывает на кнопку, пока стрелка в зоне. Попадание видно сразу, не дожидаясь сервера
	    (он судит по тому же t; нет ответа за MaxLag + 0.2 с — предсказание забывается): стрелка
	    на миг замирает и вспыхивает золотом, панель вздрагивает, искры, звук
	    всё выше, слово «ОТЛИЧНО!» → «СУПЕР!» → «МЕГА!» (или «ИДЕАЛЬНО!» — стрелка была не дальше
	    PERFECT_SHARE ширины зоны от центра: золото, звёзды, вспышка, края экрана). Последнее,
	    победное попадание — не удар, а «замирание» (holdWin): стрелка золотая стоит там, где
	    нажали, зона горит золотом, кольцо, панель вздрагивает; так до ответа сервера (не дольше
	    1.5 с, нажатия тем временем не отправляются) — праздник начинается в "Caught". Ответ сервера
	    ("Zone") переносит зону (🐟 перепрыгивает за ней) и «печатает» ⭐ в кружке попаданий.
	    Промах (Lost miss) или конец времени: мини-игра сразу закрывается, а её копия
	    (FxMinigameMiss) ещё полсекунды краснеет, качается и показывает «МИМО!» / «ВРЕМЯ!»
	    (рыба уплывает за край), потом быстро уходит вверх и тает; подсказка с причиной — когда
	    копии уже нет (MISS_HOLD).
	    Эффекты никогда не закрывают стрелку и зону.
	  • Улов (UI v2, порядок — в разделе «Улов» ниже): сначала мир, потом карточка. На
	    "Caught" копия мини-игры (FxMinigameWin) «побеждает» — ⭐, золотая зона, стрелка там,
	    где было победное нажатие — и сразу уходит вниз (не закрывает прыжок рыбы); «ПОЙМАНА!»
	    — самое громкое слово мини-игры, влетает ударом левее персонажа (не на нём и не ближе
	    16 px к джойстику — иначе ниже ростом; удар растёт от края, дальнего от них), в цветах
	    редкости, и тает до приземления (перед ударом — миг тишины); кнопка «замирает» (тусклое
	    «ЖДЁМ…»), подсказки нет, плашки статуса гаснут (рыба летит над ними); у эпической и выше
	    по краям экрана нарастает узкая рамка цвета редкости (мифическая — светлая радуга по
	    кругу) и в миг приземления обрывается, камера перед приземлением чуть «отъезжает», у
	    легендарной и мифической всё чаще бьётся «сердце». Рыба выпрыгивает и садится над головой
	    (FishingFxController.OwnFishLanded): чёткий удар в точке рыбы (тонкое кольцо и искры; на
	    весь экран — ничего: ни свечения, ни вспышки краёв),
	    тряска и «толчок» камеры, конфетти из точки над головой; у эпической и выше — лучи бьют
	    из рыбы (середина пустая) и НАД ней, вверху экрана (v3: не на рыбе и не на руках —
	    FishingLayout.topBand; где встанет рыба, считается по модели, пока сервер её ещё не
	    поставил; над огромной рыбой на телефоне места нет — слово сбоку от неё),
	    огромное слово редкости (TitleSlam: белое → цвет
	    редкости, толстая обводка; у легендарной и мифической — буквами, каждая, встав,
	    качается волной; следом за буквами по слову пробегает блик), когда кольца удара ушли —
	    экран чуть темнеет (не на телефоне: рыбак с трофеем остаётся ярким); карточка — когда
	    слово сложилось и постояло (у эпической и выше v3 — на 0.6 с дольше: видно, как рыбак
	    ловит рыбу обеими руками и поднимает её). Карточка (CatchCard)
	    рождается в точке рыбы и встаёт на место (слово летит в её баннер, баннер вырастает из
	    него, и его надпись проявляется, пока слово тает; лучи — за ней): на телефоне
	    — широкая «трофейная» (рыба слева, имя и цены справа) СБОКУ от своего рыбака, где шире
	    (v3: FishingLayout.dockSide — слева над джойстиком или справа над кнопкой действия; не
	    ниже CARD.DockMin, а места нет — посередине, как раньше), на планшете и компьютере —
	    квадратная; легендарная и мифическая — крупнее. Вокруг — затемнение (у обычной нет; на
	    телефоне — одна полоса с её стороны экрана, тающая к рыбаку, иначе — полосы сверху и
	    снизу, как в кино) и крупные лучи цветов редкости (UI v5: у карточки рядом с рыбаком их
	    слой CatchRays обрезает их у его края — до рыбака с трофеем не достают; спицы слова
	    уходят в карточку копией). Редкость видна и на самой карточке:
	    маленькие лучи за рыбой, у эпической и выше — «живая» обводка (виноград дышит, по
	    золоту бежит блик, радуга вращается; с мутацией — на баннере), у легендарной и
	    мифической — лицо в цвет редкости (у мифической по нему бежит пастельная радуга). Имя
	    рождается вместе с карточкой (въезжает справа, пока она встаёт на место). Дальше доли —
	    по одной (обычная и редкая — бодро, не ближе 0.2 с; эпическая и выше — не ближе 0.27 с):
	    редкость, «НОВИНКА!» (штамп; вид пойман впервые за игру — у обычной и редкой это ещё и
	    маленький праздник: искры, конфетти, лучи ярче, «+$4/с»), вес и цена (поднимаются), цена
	    набегает до самого «приземления» (фишка пружинит, из неё вылетает «+$4/с» — на свободное
	    место рядом с карточкой, у карточки сбоку от рыбака — над ней, у её внешнего края или под
	    ней, и только если места нет — на верх окошка с рыбой; цену не закрывает; у легендарной и
	    мифической — дождь 💰 по бокам (у карточки сбоку от рыбака — с её внешней стороны) и конфетти, у мифической — вспышка радужной обводки), у мутации цена сперва «дышит»
	    одну долю, потом штамп на углу рыбы, «×N» у цены, пересчёт (праздник — у полной цены) и
	    цветная обводка карточки; последней — «Тапни — забрать!», кнопка действия — «ЗАБРАТЬ!»,
	    и всё успокаивается (мифическая «дышит»). Тап по карточке раньше последней доли
	    показывает всё сразу, ещё через 0.6 с — может закрыть; сама карточка закрывается через
	    UIConfig.CatchCardTime[редкость] (но не раньше 0.6 с после последней доли). Уходя, она
	    сама летит снарядом в кнопку «САДОК» (сжимаясь почти в точку), рядом с ней — 🐟 со ★
	    цветов редкости; прилёт — когда долетели, а следом трофей над головой «вспыхивает» ещё раз
	    (FishingFxController.ReplayOwnTrophy; своя табличка с ценой выскакивает только теперь) —
	    рыба висит дольше карточки. Этап 3 (design §6.5): "Caught" несёт Tank — что стало с рыбой
	    в садке; на карточке — «цена $45», из фишки цены вылетает доход рыбы «+$4/с», своей долей
	    на правый нижний угол карточки шлёпается наклейка «В САДОК!» / «ЗАМЕНА!» / «САДОК ПОЛОН»
	    над «ПРОДАНА» (CatchFx.tankStamp / tankRow); рыба продана сразу (садок полон) — вылетает
	    золотое «+$15», карточка висит не меньше CatchFx.SOLD_HOLD после наклейки (cardTime), а
	    уходя, она и 💵 летят в кошелёк (Status.Wallet.Money; кнопки нет — в середину колонки
	    кнопок). «НОВИНКА!» —
	    первый улов вида за всё время (Fish.New от сервера). Фишку «4/6» кнопки «САДОК» ведёт
	    TankButtonController, кошелёк — MoneyController: от "Caught" до прилёта у HUD стоит
	    атрибут CounterHold (прошлое число улова — «улов на экране»), пока рыба летит —
	    CounterIncoming (её редкость: прилёт — в цвете редкости).
	  • Подстраховка: сервер ставит атрибут FishingState = "Idle" раньше события; если события
	    ("Caught" / "Lost" / "Idle") за полсекунды так и не было — рыбалка кончается сама.
	  • Подсказка (Hint — «таблетка» таймера из образца: тёмное стекло 💡 с курсивом / солнечная ⚠️ /
	    ягодная 🚨 плашка; значок в тёмной обводке выступает слева; выскакивает, въезжая снизу на
	    несколько px — туда, где её поставил renderHint; уходя, «вдыхает» и сжимается; шириной по
	    своему тексту — FishingLayout.hintWidth; не влезает в строку — две ровные; новый текст на
	    виду — «таблетка» плавно меняет ширину, надпись «ударяет»): почему заброс не принят, почему
	    рыба ушла, куда идти. Тексты причин — общие с сервером (FishingConfig.Texts). Если игрок
	    далеко от точки рыбалки своей базы, а удочка в руке или в рюкзаке («ВЗЯТЬ»; и сразу после
	    появления) — к ней тянется дорожка-луч (Beam, только у него) и «куда идти». v3 (WOW-6):
	    подсказка по месту (💡) уходит через HINT_INFO_TIME с; «куда идти» возвращается каждые
	    HINT_AGAIN с, пока всё ещё к месту; подсказку, чьё действие игрок уже сделал HINT_LEARNED
	    раз (забросил, взял удочку, дошёл до круга), больше не показываем («куда идти» — только
	    когда он сам дошёл до круга); подсказка по месту ждёт, пока по центру стоит баннер
	    «ТВОЯ БАЗА» (вход в игру: первая «куда идти» выскакивает целиком, когда он улетел в
	    плашку), и на телефоне — пока своя рыба над головой (луч в мире не ждёт: «ДОМОЙ» сразу
	    после улова — он уже ведёт назад).
	    Подсказка, поклёвка и мини-игра (на телефоне — кроме неё) — одна колонка внизу по центру,
	    под ногами рыбака (на телефоне подсказка, если легла бы ему на ноги, — слева от него;
	    между джойстиком и кнопкой действия; на узком экране колонка
	    сдвигается) и не показываются вместе. Панели предметов Roblox нет (HudController её
	    выключает; свою принесёт этап магазина).

	Устройство файла: большие разделы (подсказка, кнопка действия, улов, поклёвка и мини-игра,
	ответы сервера) — блоки do … end. В Luau у функции не больше 200 локальных, а весь модуль —
	одна функция: свои константы, состояние и помощники раздела живут внутри блока, а то, что
	нужно дальше по файлу, объявлено прямо перед ним. Запас проверяет tests/compile_limits.

	Уборка: всё, что живёт с персонажем, — в characterTrove; пока удочка в руке — в rodTrove;
	анимации текущего состояния — в phaseTrove (кадровые эффекты — шлейф, искры, радуга,
	полоска поклёвки — останавливаются вместе с состоянием); «фон» вида кнопки — в lookTrove;
	от "Caught" до карточки (ожидание приземления, слово редкости) — в catchTrove; карточка
	улова — в cardTrove, её лучи — в raysTrove; конфетти, дождь 💰 и полёт 🐟, которые
	доигрывают после карточки, — в celebrationTrove. В покое (ничего не происходит) — ни одного
	покадрового соединения: только таймеры и твины.

	Запуск (Start): сначала разметка колонки и персонаж — опрос при нём единственный показывает
	кнопку; оформление (колонка, «сжатие» кнопок) и помощник FishingFxController — под защитой:
	упавшее в настоящем Roblox — красная ошибка с именем шага, а кнопка остаётся. Недостающий
	элемент HUD (child) — через 5 с ошибка с путём, а не вечное ожидание (ClientMain тогда
	запускает остальные контроллеры).
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local FishingConfig = require(Config:WaitForChild("FishingConfig"))
local UIConfig = require(Config:WaitForChild("UIConfig"))
local FishingRules = require(Shared:WaitForChild("FishingRules"))
local Net = require(Shared:WaitForChild("Net"))
local UiFx = require(Shared:WaitForChild("UiFx"))
local Trove = require(Shared:WaitForChild("Util"):WaitForChild("Trove"))

local player = Players.LocalPlayer

local ACTION_NAME = "FishingAction"
-- «ВЗЯТЬ» с клавиатуры / геймпада: 1 (как прежняя панель предметов), F, R2; с удочкой в руке 1 её убирает.
local TAKE_ACTION, STOW_ACTION = "FishingTake", "FishingStow"
local ACTION_DEBOUNCE = 0.05 -- одно нажатие могут поймать два пути ввода (кнопка + удочка)
local CONTEXT_CHECK_INTERVAL = 0.25 -- как часто проверять, у точки ли рыбалки игрок, с
local CARD_INPUT_LOCK = 0.35 -- столько секунд после появления карточка не слушает тапы
local PERFECT_SHARE = 0.25 -- «ИДЕАЛЬНО!»: стрелка не дальше этой доли ширины зоны от её центра
local MISS_HOLD = 0.75 -- столько живёт копия мини-игры после промаха (с уходом); потом — подсказка, с
local DIM_TIME = 0.25 -- затемнение за карточкой появляется / уходит, с

local TEXTS = FishingConfig.Texts -- тексты причин, общие с сервером (FishingConfig.Texts)

local Palette = UIConfig.Palette
local WHITE = UIConfig.White

local COLORS = {
	PipDone = UIConfig.Fishing.PipDone, -- закрашенный кружок попадания (его ищут тесты)
	Guide = UIConfig.Fishing.Guide,
}

type Phase = "Idle" | "Pending" | "Waiting" | "Bite" | "Reeling"

-- Вид кнопки действия: цвет — токен палитры UIConfig, Ring — белый ореол (прозрачность, цвет).
-- Glyph — значок не эмодзи, а знак текстом (белый → золотой, с обводкой): «!» поклёвки;
-- Bobber — вместо значка нарисованный поплавок (ожидание поклёвки); Flash — важная смена вида:
-- кнопка «превращается» (белая вспышка, значок выскакивает — UiFx.morphFlash).
type Look = {
	Name: string,
	Caption: string,
	Icon: string,
	Token: string,
	Key: boolean,
	Ring: number,
	RingColor: Color3,
	Glyph: boolean?,
	Bobber: boolean?,
	Flash: boolean?,
}

local CAST_LOOK: Look = {
	Name = "Cast",
	Caption = "ЗАБРОСИТЬ",
	Icon = "🎣",
	Token = "Sky",
	Key = true,
	Ring = 0.6,
	RingColor = WHITE,
}
local WAIT_LOOK: Look = {
	Name = "Wait",
	Caption = "ЖДЁМ…",
	Icon = "⏳",
	Token = "Slate",
	Key = false,
	Ring = 1,
	RingColor = WHITE,
}
-- Леска в воде, ждём поклёвку: приглушённая «водяная» кнопка с поплавком (WATER_DOTS — бегущие
-- точки). v3 (UIM-09): не похожа на кнопку, которую надо жать, — меньше (WATER_SMALL), тише по
-- цвету (Pond), без расходящихся кругов, надпись «ЖДИ КЛЁВА…».
local WATER_LOOK: Look = {
	Name = "Water",
	Caption = "ЖДИ КЛЁВА…",
	Icon = "",
	Token = "Pond",
	Key = false,
	Ring = 1,
	RingColor = WHITE,
	Bobber = true,
}
local BITE_LOOK: Look = {
	Name = "Bite",
	Caption = "ПОДСЕЧЬ!",
	Icon = "!",
	Token = "Sun",
	Key = true,
	Ring = 0,
	RingColor = WHITE,
	Glyph = true,
	Flash = true,
}
local REEL_LOOK: Look = {
	Name = "Reel",
	Caption = "ЛОВИ!",
	Icon = "🎯",
	Token = "Leaf",
	Key = true,
	Ring = 0.35,
	RingColor = WHITE,
	Flash = true,
}

-- Надписи и цвета попаданий: от попадания к попаданию всё громче (третье и дальше — радуга),
-- идеальное — золотом.
type HitWord = { text: string, colors: { Color3 }, rainbow: boolean? }

type Minigame = {
	Rarity: string,
	U0: number,
	Speed: number,
	ZoneCenter: number,
	ZoneWidth: number,
	Hits: number,
	HitsNeeded: number,
	Timeout: number,
}

type Ui = {
	hud: ScreenGui,
	actionButton: GuiButton,
	actionIcon: TextLabel,
	actionCaption: TextLabel,
	actionRing: UIStroke,
	stopButton: GuiButton,
	biteAlert: Frame,
	biteLabel: TextLabel,
	biteTimer: Frame,
	biteIcons: { GuiObject },
	minigame: Frame,
	title: TextLabel,
	titleFill: UIGradient,
	pips: { Frame },
	track: Frame,
	zone: Frame,
	zoneGlow: Frame,
	zoneFlash: Frame,
	needle: Frame,
	timeFill: Frame,
	hint: TextLabel,
	hintLabel: TextLabel,
	hintIcon: TextLabel,
	dim: Frame,
	rays: Frame,
	card: GuiButton,
	banner: Frame,
	bannerFill: UIGradient,
	rarityLabel: TextLabel,
	fishGlow: Frame,
	viewport: ViewportFrame,
	newStamp: Frame,
	nameLabel: TextLabel,
	nameFill: UIGradient,
	mutationLabel: TextLabel,
	mutationFill: UIGradient,
	mutationIcon: TextLabel,
	mutationCaption: TextLabel,
	infoLabel: TextLabel,
	weightChip: Frame,
	weightLabel: TextLabel,
	priceChip: Frame,
	priceIcon: GuiObject,
	priceLabel: TextLabel,
	counter: GuiObject, -- Этап 3: кнопка «САДОК» (RightButtons.TankButton) — туда летит улов
	wallet: GuiObject, -- … а рыба, проданная сразу, — 💵 в кошелёк (Status.Wallet.Money)
	tankStamp: Frame, -- наклейка садка на углу «В САДОК!» / «ЗАМЕНА!» / «САДОК ПОЛОН · ПРОДАНА»
	-- Баннер «ТВОЯ БАЗА» по центру (его ведёт HudController): пока он виден, подсказка по месту ждёт.
	baseBanner: GuiObject?,

	-- Улов, UI v2 (FUI-01…12): корень Fishing, плашки статуса (гаснут под карточкой), подсказка
	-- «закрыть», рамка мутации, «×N» у цены, огромное слово редкости (TitleSlam).
	fishing: Frame,
	status: Frame,
	tapHint: TextLabel,
	cardOutline: UIStroke,
	priceMult: TextLabel,
	titleSlam: Frame,
	titleLabel: TextLabel,
	titleSlamFill: UIGradient,
	titleLetters: Frame,
	dimBands: { Frame },
	-- UI v2, игра (кнопка, поклёвка, мини-игра, подсказка):
	actionArea: Frame,
	actionOutline: UIStroke, -- тёмный контур значка на кнопке (у знака «!» толще)
	actionFill: UIGradient, -- его заливка белый → золотой
	actionBobber: Frame, -- поплавок вместо значка, пока ждём поклёвку
	keyChip: Frame,
	keyLabel: TextLabel,
	tapCue: TextLabel, -- 👇 новичку
	stopCaption: TextLabel,
	aura: UIStroke, -- обводка панели мини-игры в цвет редкости (эпическая и выше)
	auraFill: UIGradient,
	rider: TextLabel, -- 🐟 на зоне
	timeBar: Frame,
	pipsFrame: Frame,
	tapPad: GuiButton, -- касание панели мини-игры = нажатие (тач-экран)
	biteTapPad: GuiButton, -- касание плашки «КЛЮЁТ!» = подсечка (тач-экран)
	hintSocket: Frame,
	pedestal: Frame, -- подиум рыбы на карточке (в цвет редкости)
	window: Frame, -- v3: окошко рыбы на карточке (туда летит «+$4/с», когда карточка сбоку от рыбака)
}

-- Исходные значения из шаблона HUD (возвращаются после анимаций).
type Defaults = {
	minigamePosition: UDim2,
	biteTimerSize: UDim2,
	biteTimerColor: Color3,
	zoneHeight: number,
	needleY: number,
	pipColor: Color3,
	hintPosition: UDim2,
	iconRotation: number,
	dimTransparency: number,
	trackLeft: number,
	trackWidth: number,
	trackMidY: number,
	namePosition: UDim2,
	mutationPosition: UDim2,
	-- UI v2, игра:
	alertPosition: UDim2,
	hintSize: UDim2,
	riderY: number,
	glowSize: UDim2,
	timeBarSize: UDim2,
	bobberPosition: UDim2,
	tapCuePosition: UDim2,
	stopPosition: UDim2,
	stopSize: UDim2,
	minigameSize: UDim2,
	actionSize: UDim2, -- v3: кнопка действия «в покое» (ожидание поклёвки её уменьшает)
	actionBuilt: UDim2, -- … её размер из сборщика (на планшете в покое она меньше: layoutColumn)
	actionPosition: UDim2,
	captionSize: UDim2, -- … её надпись и плашка подписи (при ожидании — прежней ширины в px)
	ribbonSize: UDim2,
}

type Guide = { beam: Beam, from: Attachment, to: Attachment, spot: BasePart }

local FishingController = {}

local ui: Ui
local defaults: Defaults
local keyHint = ""

local phase: Phase = "Idle"
local rod: Tool? = nil -- удочка в руке
local offerTake = false -- кнопка «ВЗЯТЬ» (удочка в рюкзаке; есть база, персонаж жив)
local castReadyAt = 0 -- os.clock(), с которого сервер снова примет заброс (CastCooldown)
local cardOpenedAt = -math.huge
local catchScreen = false -- улов на экране: от "Caught" до прилёта 🐟 в счётчик (FUI-09)
local cardSettled = true -- все доли карточки показаны: тап закрывает (кнопка — «ЗАБРАТЬ!»)
local hookSent = false
local minigame: Minigame? = nil
local minigameStart = 0 -- os.clock() получения "Minigame"
local lastTap = -math.huge
local lastAction = -math.huge
local tapNeedle: number? = nil -- где была стрелка при последнем нажатии в мини-игре
local tapZone: number? = nil -- … и где была зона
local pendingThread: thread? = nil
local guide: Guide? = nil
local seenSpecies: { [string]: boolean } = {} -- какие виды уже ловили за эту игру («НОВАЯ!»)

local characterTrove = Trove.new()
local rodTrove = Trove.new()
local phaseTrove = Trove.new()
local actionPulseTrove = Trove.new() -- пульс и свечение кнопки на поклёвке (гаснут после подсечки)
local cardTrove = Trove.new()
local celebrationTrove = Trove.new() -- конфетти и полёт 🐟 (доигрывают после карточки)

--------------------------------------------------------------------------------
-- Мелкие помощники
--------------------------------------------------------------------------------

-- Число из данных сервера: только конечные числа, иначе default.
local function number(value: any, default: number): number
	if typeof(value) == "number" and value == value and math.abs(value) ~= math.huge then
		return value
	end
	return default
end

-- Заглавные буквы, включая кириллицу (string.upper меняет только латиницу).
local function upper(text: string): string
	local out = {}
	for _, code in utf8.codes(text) do
		if (code >= 0x430 and code <= 0x44F) or (code >= 0x61 and code <= 0x7A) then
			code -= 0x20
		elseif code == 0x451 then
			code = 0x401 -- ё → Ё
		end
		table.insert(out, utf8.char(code))
	end
	return table.concat(out)
end

-- Элемент интерфейса по имени. HUD приходит клиенту целиком (StarterGui → PlayerGui, стриминга
-- нет), ждать по сути нечего: недостающее имя (HUD поправили в Studio, место старее скриптов) —
-- через CHILD_WAIT с громкая ошибка с путём, а не вечное «Infinite yield possible» и кнопка
-- рыбалки, которая так и не появилась.
local function child(parent: Instance, name: string): any
	local CHILD_WAIT = 5
	local found = parent:FindFirstChild(name) or parent:WaitForChild(name, CHILD_WAIT)
	if not found then
		error(
			`[FishingController] нет {parent:GetFullName()}.{name}: пересобери место (tools/build.luau)`,
			2
		)
	end
	return found
end

-- fn() через delay секунд; отменяется уборкой trove.
local function later(trove: Trove.Trove, delay: number, fn: () -> ())
	trove:Add(task.delay(delay, fn))
end

-- fn() каждые interval секунд (первый раз — через first), пока trove не убран. Только таймеры.
local function every(trove: Trove.Trove, interval: number, fn: () -> (), first: number?)
	local running = true
	local pending: thread? = nil
	local function tick()
		pending = nil
		if not running then
			return
		end
		fn()
		pending = task.delay(interval, tick)
	end
	pending = task.delay(first or interval, tick)
	trove:Add(function()
		running = false
		local thread = pending
		pending = nil
		if thread and coroutine.status(thread) == "suspended" then
			task.cancel(thread)
		end
	end)
end

local function swatchOf(
	style: { Top: Color3, Bottom: Color3, Lip: Color3 }
): { Top: Color3, Bottom: Color3, Lip: Color3 }
	return { Top = style.Top, Bottom = style.Bottom, Lip = style.Lip }
end

-- Копия виджета, которая «доигрывает», когда сам он уже спрятан (мини-игра побеждает или
-- промахивается): не ловит касаний (без TapPad, Active = false) и не тащит за собой эффекты
-- живого виджета (слова, искры, лучи, шлейф стрелки, вспышки — всё Fx*, кроме масштаба FxScale).
local function ghostOf(source: GuiObject, name: string): GuiObject
	local ghost = source:Clone()
	ghost.Name = name
	ghost.Visible = true
	ghost.Active = false
	local strip: { Instance } = {}
	for _, item in ghost:GetDescendants() do
		local itemName = item.Name
		if itemName == "TapPad" or (string.sub(itemName, 1, 2) == "Fx" and itemName ~= "FxScale") then
			table.insert(strip, item)
		end
	end
	for _, item in strip do
		if item.Parent then
			item:Destroy()
		end
	end
	ghost.Parent = source.Parent
	return ghost
end

local function isRod(instance: Instance): boolean
	return instance:IsA("Tool") and typeof(instance:GetAttribute("RodId")) == "string"
end

local function isAlive(): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function hasBase(): boolean
	local index = player:GetAttribute("BaseIndex")
	return typeof(index) == "number" and index > 0
end

-- Удочка в рюкзаке (не в руке).
local function backpackRod(): Tool?
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return nil
	end
	for _, item in backpack:GetChildren() do
		if isRod(item) then
			return item :: Tool
		end
	end
	return nil
end

local function isLineOut(): boolean
	return phase == "Waiting" or phase == "Bite" or phase == "Reeling"
end

local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Точка рыбалки своей базы: Workspace.Bases.* с тем же BaseIndex, что у игрока.
local function ownFishingSpot(): BasePart?
	local index = player:GetAttribute("BaseIndex")
	local bases = Workspace:FindFirstChild("Bases")
	if typeof(index) ~= "number" or index <= 0 or not bases then
		return nil
	end
	for _, base in bases:GetChildren() do
		if base:GetAttribute("BaseIndex") == index then
			local spot = base:FindFirstChild("FishingSpot")
			return if spot and spot:IsA("BasePart") then spot else nil
		end
	end
	return nil
end

-- У точки рыбалки: допуск сервера (SpotRadius по горизонтали, SpotMaxHeight по высоте), но по
-- горизонтали на SPOT_MARGIN стадов строже. Сервер проверяет заброс по своей копии персонажа, а
-- она в настоящей игре отстаёт на пинг (идя к кругу со скоростью 16 — на 2–5 стадов): кнопка,
-- ставшая «ЗАБРОСИТЬ» на самом краю, не должна в тот же миг получить отказ «далеко».
local function isNearSpot(root: BasePart, spot: BasePart): boolean
	local SPOT_MARGIN = 2
	local offset = root.Position - spot.Position
	local horizontal = Vector3.new(offset.X, 0, offset.Z).Magnitude
	return horizontal <= FishingConfig.SpotRadius - SPOT_MARGIN and math.abs(offset.Y) <= FishingConfig.SpotMaxHeight
end

--------------------------------------------------------------------------------
-- Подсказка внизу экрана и дорожка к точке рыбалки
--------------------------------------------------------------------------------

-- Наружу из раздела (блок do … end, см. «Устройство файла» в шапке):
local laidOutFor: Vector2? = nil -- размер HUD, под который колонка разложена
local hintHeldUntil = 0
local layoutColumn, showHint, clearEventHint, setContextHint, destroyGuide, setGuide, keepClearOfBobber, fisherRect
local slamRoom
do
	local Layout = require(script.Parent:WaitForChild("FishingLayout")) -- раскладка у своего рыбака
	local HINT_TIME = 3.5 -- сколько висит подсказка о событии, с
	-- Подсказка по месту (💡, всегда «info») сама уходит через HINT_INFO_TIME с; навигационные
	-- (куда идти) возвращаются через again секунд, пока всё ещё к месту (setContextHint).
	local HINT_INFO_TIME = 4
	local SHORT_SCREEN = 500 -- HUD ниже — телефон: виджеты не закрывают своего рыбака (FishingLayout)

	-- Значок подсказки по её виду (в белом кружке) и цвет плитки (палитра UIConfig).
	local HINT_ICONS: { [string]: string } = {
		info = "💡",
		warning = "⚠️",
		success = "🎉",
		danger = "🚨",
	}

	local HINT_TOKENS: { [string]: string } = {
		warning = "Sun",
		danger = "Berry",
	}

	local hintThread: thread? = nil
	local eventHint: { text: string, kind: string }? = nil
	local contextHint: string? = nil
	local contextAgain: number? = nil -- через сколько навигационная подсказка возвращается, с
	local contextFaded = false -- подсказка по месту уже отвисела HINT_INFO_TIME (до смены текста)
	local contextTimer: thread? = nil

	--[[
		Центральная колонка (подсказка, поклёвка, мини-игра) стоит по центру экрана, но не ближе
		COLUMN_GAP к джойстику (тач-экран) и к кнопке действия с её лентой подписи: на узком
		экране (маленький телефон, планшет 4:3) колонка сдвигается влево, а подсказка ещё и
		сужается. Сдвиг — Position.X.Offset (X.Scale остаётся 0.5); пересчёт — при смене размера HUD.
	]]
	local COLUMN_GAP = 24 -- до джойстика и кнопки действия (с запасом на обводки и рамку редкости), px
	-- Мини-игра по центру (планшет, ПК): от её рамки редкости до джойстика и ленты подписи кнопки — не
	-- меньше MINI_GAP px и ещё MINI_JUICE её ширины в каждую сторону на «приземление» и удары.
	local MINI_GAP, MINI_JUICE = 18, 0.05
	local spanLeft, spanRight = 0, math.huge -- просвет колонки без значка подсказки, px (layoutColumn)
	-- Кнопки Roblox на тач-экране (короткая сторона экрана ≤ 500 px — маленькие): правый край
	-- джойстика от левого края, px; кнопка прыжка — FishingLayout.JUMP_SMALL / JUMP_BIG.
	local STICK_SMALL, STICK_BIG = 95, 180

	local function smallTouchScreen(): boolean
		local camera = Workspace.CurrentCamera
		local view = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		return math.min(view.X, view.Y) <= 500
	end

	-- Ширина и высота элемента по его Size (или size), SizeConstraint и UISizeConstraint (в px) —
	-- без AbsoluteSize: раскладка верна, даже пока HUD ещё не измерен.
	local function boxSize(gui: GuiObject, width: number, height: number, override: UDim2?): Vector2
		local size = override or gui.Size
		local yy = gui.SizeConstraint == Enum.SizeConstraint.RelativeYY
		local w = size.X.Scale * (if yy then height else width) + size.X.Offset
		local h = size.Y.Scale * height + size.Y.Offset
		local cap = gui:FindFirstChildOfClass("UISizeConstraint")
		if cap then
			w = math.clamp(w, cap.MinSize.X, cap.MaxSize.X)
			h = math.clamp(h, cap.MinSize.Y, cap.MaxSize.Y)
		end
		return Vector2.new(w, h)
	end

	-- Свойство меняется, только если значение другое (без лишних событий раскладки).
	local function assign(gui: GuiObject, key: "Size" | "Position", value: UDim2)
		if (gui :: any)[key] ~= value then
			(gui :: any)[key] = value
		end
	end

	function layoutColumn()
		local size = ui.hud.AbsoluteSize
		local width, height = size.X, size.Y
		if width < 2 or height < 2 then
			return
		end
		laidOutFor = size
		local touch = UserInputService.TouchEnabled
		local small = smallTouchScreen()
		-- Кнопка действия — у левого края своей области: круг с якорем в центре, его левый край в
		-- 2 px левее края области (точно, в px: у области с потолком 320 x 240 доля ширины сдвинула
		-- бы его); лента подписи шире круга. На тач-экране круг меньше, если иначе его белые кольца
		-- на пике пульса подошли бы к кнопке прыжка ближе 16 px (FishingLayout.discFit: на планшете
		-- ≈ 0.9, левый край и низ на месте — левее колонка подсказки и карточка улова).
		local area = boxSize(ui.actionArea, width, height)
		local built = defaults.actionBuilt.Y.Scale * area.Y -- (размер из сборщика)
		local rest = defaults.actionPosition
		local discLeft = -2
		local shrink = 1
		if touch then
			local ringPx = Layout.RING.thickness * math.clamp(height / 720, 0.65, UIConfig.Fx.StrokeMax)
			local bottom = height - area.Y + rest.Y.Scale * area.Y + built / 2
			shrink = Layout.discFit(width - area.X + discLeft, bottom, built / 2, size, small, ringPx, 0.8)
		end
		local sized = UDim2.fromScale(defaults.actionBuilt.X.Scale * shrink, defaults.actionBuilt.Y.Scale * shrink)
		if sized ~= defaults.actionSize then -- (новый экран; ожидание поклёвки уменьшит её снова)
			defaults.actionSize = sized
			assign(ui.actionButton, "Size", sized)
		end
		local button = sized.Y.Scale * area.Y -- (в покое: ожидание её уменьшает)
		rest = UDim2.new(0, math.ceil(discLeft + button / 2), rest.Y.Scale, math.floor((built - button) / 2))
		assign(ui.actionButton, "Position", rest)
		defaults.actionPosition = rest
		local ribbon = ui.actionButton:FindFirstChild("CaptionRibbon")
		local overhang = if ribbon and ribbon:IsA("GuiObject")
			then button * math.max(ribbon.Size.X.Scale - 1, 0) / 2
			else 0
		-- (Обводки ленты и плитки подсказки — снаружи их рамок: на планшете по 4.5 px. v3: без
		-- хотбара подсказка стоит вровень с лентой подписи — зазор меряется по обводкам.)
		local function lipStroke(gui: Instance?): number
			local lip = gui and gui:FindFirstChild("Lip")
			local stroke = lip and lip:FindFirstChildOfClass("UIStroke")
			return if stroke then UiFx.strokeThickness(stroke) else 0
		end
		local right = width - area.X + discLeft - overhang - lipStroke(ribbon) - lipStroke(ui.hint) - COLUMN_GAP
		-- На сколько кнопке действия можно вырасти (пульс поклёвки, удар попадания), чтобы с обводкой
		-- держать 16 px до кнопки прыжка (тач-экран; на планшете та большая и выше): атрибут GrowMax.
		local grow = 1.2
		if touch then
			local jump, jumpRadius = Layout.jumpCircle(Vector2.new(width, height), small)
			local center =
				Vector2.new(width - area.X + rest.X.Offset, height - area.Y + rest.Y.Scale * area.Y + rest.Y.Offset)
			local radius = button / 2 + lipStroke(ui.actionButton)
			grow = math.clamp(((center - jump).Magnitude - jumpRadius - 16) / radius, 1.02, grow)
		end
		ui.actionButton:SetAttribute("GrowMax", grow)
		-- Слева — джойстик; значок подсказки в кружке выступает за её левый край вместе с обводкой
		-- (а выскакивая — с перелётом, ещё на несколько px: запас 4 px на тач-экране).
		local socket = ui.hintSocket
		local hintHeight = boxSize(ui.hint, width, height).Y
		local ring = socket:FindFirstChildOfClass("UIStroke")
		local socketOut = socket.Size.X.Scale * hintHeight * socket.AnchorPoint.X
			+ (if ring then ring.Thickness else 0)
			+ (if touch then 4 else 0)
		local left = (if touch then (if small then STICK_SMALL else STICK_BIG) else 0) + COLUMN_GAP + socketOut
		spanLeft, spanRight = left - socketOut, right
		-- Подсказка и мини-игра сужаются до просвета (планшет 4:3, маленький телефон); их
		-- содержимое — в долях, а MinSize панели не даёт ей стать нечитаемой.
		local function fit(gui: GuiObject, rest: UDim2, room: number?): number
			local target = rest
			local yy = gui.SizeConstraint == Enum.SizeConstraint.RelativeYY
			local cap = gui:FindFirstChildOfClass("UISizeConstraint")
			local w = rest.X.Scale * (if yy then height else width) + rest.X.Offset
			if cap then
				w = math.clamp(w, cap.MinSize.X, cap.MaxSize.X)
			end
			local span = room or (right - left)
			if w > span and span > 0 then
				w = math.floor(math.max(span, if cap then cap.MinSize.X else 0))
				target = UDim2.new(0, w, rest.Y.Scale, rest.Y.Offset) -- смещение UDim — целые пиксели
			end
			assign(gui, "Size", target)
			return w
		end
		-- Подсказка — по своему тексту (не пустая полоса на полэкрана); мини-игра на телефоне встаёт
		-- слева от рыбака (keepClearOfBobber, dock) — центр колонки её не учитывает.
		-- Не влезает в одну строку — две ровные (место — и потолок «таблетки», и просвет колонки).
		local hint = ui.hint
		local hintRest = defaults.hintSize
		local hintCap = hint:FindFirstChildOfClass("UISizeConstraint")
		local bodySize = UiFx.textSize("Body")
		local hintWant = Layout.hintWidth(
			ui.hint.Text,
			bodySize,
			boxSize(hint, width, height).Y,
			math.min(
				hintRest.X.Scale * width + hintRest.X.Offset,
				if hintCap then hintCap.MaxSize.X else math.huge,
				if right > left then right - left else math.huge
			),
			UiFx.textWidth(ui.hint.Text, bodySize),
			function(piece: string): number
				return UiFx.textWidth(piece, bodySize)
			end
		)
		-- Мини-игра на планшете и ПК (по центру колонки; на телефоне она встаёт у рыбака): её рамка
		-- редкости (AuraStroke) шире обводки, а «приземление» (перелёт pop-in и сплющивание 1.08) и
		-- удар попадания (1.06) раздувают её ещё на MINI_JUICE ширины в каждую сторону — запас на
		-- всё это, чтобы и на пике до ленты подписи кнопки и до джойстика было ≥ 16 px (SIMB-C2-02).
		local miniLo, miniHi, miniReserve = left, right, 0
		local miniRoom: number? = nil
		if height >= SHORT_SCREEN then
			local aura = ui.minigame:FindFirstChild("AuraStroke")
			local auraPx = if aura and aura:IsA("UIStroke") then UiFx.strokeThickness(aura) else 0
			miniLo = (if touch then (if small then STICK_SMALL else STICK_BIG) else 0) + MINI_GAP + auraPx
			miniHi = width - area.X + discLeft - overhang - lipStroke(ribbon) - MINI_GAP - auraPx
			miniRoom = math.floor((miniHi - miniLo) / (1 + 2 * MINI_JUICE))
		end
		local mini = fit(ui.minigame, defaults.minigameSize, miniRoom)
		if miniRoom then
			miniReserve = math.ceil(MINI_JUICE * mini)
		end
		local widest = math.max(
			fit(hint, UDim2.new(0, hintWant, hintRest.Y.Scale, hintRest.Y.Offset)),
			boxSize(ui.biteAlert, width, height).X,
			if height < SHORT_SCREEN then 0 else mini
		)
		local center = width / 2
		if right - left >= widest then
			center = math.clamp(center, left + widest / 2, right - widest / 2)
		else
			center = (left + right) / 2
		end
		local shift = math.floor(center - width / 2 + 0.5)
		local function place(gui: GuiObject, rest: UDim2): UDim2
			local placed = UDim2.new(rest.X.Scale, shift, rest.Y.Scale, rest.Y.Offset)
			assign(gui, "Position", placed)
			return placed
		end
		defaults.hintPosition = place(hint, defaults.hintPosition)
		defaults.alertPosition = place(ui.biteAlert, defaults.alertPosition)
		if miniRoom and miniHi - miniLo >= mini + 2 * miniReserve then
			-- (своя середина, если общая подвела бы её к краю ближе запаса)
			local own = math.clamp(width / 2 + shift, miniLo + miniReserve + mini / 2, miniHi - miniReserve - mini / 2)
			local miniRest = defaults.minigamePosition
			local placed =
				UDim2.new(miniRest.X.Scale, math.floor(own - width / 2 + 0.5), miniRest.Y.Scale, miniRest.Y.Offset)
			assign(ui.minigame, "Position", placed)
			defaults.minigamePosition = placed
		else
			defaults.minigamePosition = place(ui.minigame, defaults.minigamePosition)
		end

		-- «СМОТАТЬ» над кнопкой действия: на большом тач-экране (планшет) кнопка прыжка выше —
		-- тогда кнопка поднимается, чтобы между ними было COLUMN_GAP; поднятая, она встаёт рядом
		-- с колонкой кнопок справа («ДОМОЙ») — и сужается, если до неё ближе COLUMN_GAP (левый край
		-- не двигается: слева от него — карточка улова). Якорь «СМОТАТЬ» — правый нижний угол:
		-- выскакивая с перелётом, она растёт влево и вверх, к «ДОМОЙ» не приближается.
		local stop = ui.stopButton
		rest = defaults.stopPosition
		local restSize = defaults.stopSize
		local stopSize =
			Vector2.new(restSize.X.Scale * area.X + restSize.X.Offset, restSize.Y.Scale * area.Y + restSize.Y.Offset)
		local stopCap = stop:FindFirstChildOfClass("UISizeConstraint")
		if stopCap then
			stopSize = Vector2.new(stopSize.X, math.max(stopSize.Y, stopCap.MinSize.Y)) -- не ниже 44 px
		end
		local anchor = stop.AnchorPoint
		local stopRight = width - area.X + rest.X.Scale * area.X + rest.X.Offset + (1 - anchor.X) * stopSize.X
		local stopBottom = height - area.Y + rest.Y.Scale * area.Y + rest.Y.Offset + (1 - anchor.Y) * stopSize.Y
		local lift = 0
		if touch then
			local jump = if small then Layout.JUMP_SMALL else Layout.JUMP_BIG
			local jumpLeft = width - jump.right - jump.size
			local jumpTop = height - jump.bottom - jump.size
			if stopRight + COLUMN_GAP > jumpLeft and stopBottom + COLUMN_GAP > jumpTop then
				lift = math.ceil(stopBottom + COLUMN_GAP - jumpTop)
			end
		end
		local narrow = 0
		local column = ui.hud:FindFirstChild("RightButtons")
		if column and column:IsA("GuiObject") then
			local box = boxSize(column, width, height)
			local columnLeft = column.Position.X.Scale * width + column.Position.X.Offset - column.AnchorPoint.X * box.X
			local columnBottom = column.Position.Y.Scale * height
				+ column.Position.Y.Offset
				+ (1 - column.AnchorPoint.Y) * box.Y
			-- Лента подписи кнопок колонки шире самих кнопок.
			local ribbonOut = 0
			for _, item in column:GetChildren() do
				local band = item:FindFirstChild("CaptionRibbon")
				if item:IsA("GuiObject") and band and band:IsA("GuiObject") then
					ribbonOut = math.max(ribbonOut, box.X * (band.Size.X.Scale - 1) / 2)
				end
			end
			columnLeft -= ribbonOut
			local stopTop = stopBottom - lift - stopSize.Y
			if stopTop < columnBottom + COLUMN_GAP then
				-- (+ толстая обводка «СМОТАТЬ»: она снаружи рамки.)
				narrow = math.max(math.ceil(stopRight + COLUMN_GAP + lipStroke(stop) - columnLeft), 0)
			end
		end
		assign(
			stop,
			"Position",
			UDim2.new(rest.X.Scale, rest.X.Offset - math.round(narrow * anchor.X), rest.Y.Scale, rest.Y.Offset - lift)
		)
		assign(
			stop,
			"Size",
			UDim2.new(restSize.X.Scale, restSize.X.Offset - narrow, restSize.Y.Scale, restSize.Y.Offset)
		)
	end

	-- Подсказка въезжает снизу с пружиной, значок выскакивает (у предупреждения — ещё и качается, у
	-- подсказки по месту 💡 — пару раз подпрыгивает). Въезд — всего на HINT_RISE px (не на долю
	-- экрана: под подсказкой край экрана, и даже в начале въезда до него ≥ 16 px); «пружину» делает
	-- выскакивание. Едет она туда, куда её только что поставил renderHint (на телефоне — рядом с
	-- рыбаком, если на месте по умолчанию легла бы ему на ноги), а не на место по умолчанию.
	local HINT_RISE = 6
	local HINT_MORPH = 0.2 -- подсказка на виду сменила текст: «таблетка» меняет ширину за столько, с
	local function animateHint(kind: string)
		local hint = ui.hint
		local rest = hint.Position
		hint.Position = rest + UDim2.fromOffset(0, HINT_RISE)
		UiFx.tween(hint, 0.42, { Position = rest }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		UiFx.popIn(hint, { from = 0.7, time = 0.35 })
		UiFx.popIn(ui.hintSocket, { from = 0, time = 0.4, delay = 0.08, rotate = -25 })
		if kind == "warning" or kind == "danger" then
			task.delay(0.45, function()
				if hint.Visible then
					UiFx.wiggle(ui.hintSocket, 16, 3, 0.45)
				end
			end)
		else
			local icon = ui.hintIcon
			icon.AnchorPoint = Vector2.new(0.5, 0.5) -- (прошлое подпрыгивание могло прерваться в воздухе)
			UiFx.bob(icon, { hops = 2, every = { 1, 1.5 }, lift = 0.12 })
		end
	end

	-- Пока на месте подсказки доигрывает копия мини-игры (промах), подсказка ждёт (os.clock()).

	-- Подсказка о событии (eventHint) важнее постоянной подсказки по месту (contextHint).
	-- Цвет плитки — по виду: предупреждение — солнечная, опасность — ягодная, остальное — тёмная.
	local function renderHint(force: boolean?)
		local hint = ui.hint
		local text: string? = nil
		local kind = "info"
		if eventHint then
			text, kind = eventHint.text, eventHint.kind
		elseif contextHint then
			text = contextHint
		end
		if not eventHint and contextFaded then
			text = nil -- подсказка по месту отвисела своё (WOW-6): не висит над рыбаком всю игру
		end
		-- Уходя, подсказка «вдыхает» и сжимается (UiFx.popOut, 0.16 с; атрибут HintLeaving), потом
		-- прячется — если её за это время не показали снова (номер показа HintGen тот же). Сразу —
		-- когда её место заняли поклёвка и мини-игра (там уже летит своё) или копия мини-игры.
		local leaving = hint:GetAttribute("HintLeaving") == true
		if not text or os.clock() < hintHeldUntil then
			local calm = phase ~= "Bite" and phase ~= "Reeling" and os.clock() >= hintHeldUntil
			if not hint.Visible or (calm and leaving) then
				return
			end
			local gen = ((hint:GetAttribute("HintGen") :: number?) or 0) + 1
			hint:SetAttribute("HintGen", gen)
			hint:SetAttribute("HintLeaving", calm or nil)
			if not calm then
				hint.Visible = false
				return
			end
			UiFx.popOut(hint, { time = 0.16, to = 0.6 })
			task.delay(0.16, function()
				if hint:GetAttribute("HintGen") == gen then
					hint:SetAttribute("HintLeaving", nil)
					hint.Visible = false
					UiFx.scaleOf(hint).Scale = 1
				end
			end)
			return
		end
		if leaving then
			hint:SetAttribute("HintGen", ((hint:GetAttribute("HintGen") :: number?) or 0) + 1) -- снова на виду: не прятать
			hint:SetAttribute("HintLeaving", nil)
		end
		local changed = force == true or not hint.Visible or leaving or hint.Text ~= text
		local icon = HINT_ICONS[kind] or HINT_ICONS.info
		-- Та же подсказка по месту сменила текст на виду (того же вида): без нового выскока.
		local roll = changed and not force and hint.Visible and not leaving and ui.hintIcon.Text == icon
		local fromSize, fromPosition = hint.Size, hint.Position
		hint.Text = text
		if changed then
			layoutColumn() -- ширина «таблетки» — по тексту
			if ui.fishing.AbsoluteSize.Y < SHORT_SCREEN then
				-- v3: на телефоне — не на ногах своего рыбака (камера рыбалки опускает его к низу).
				local position, size = keepClearOfBobber(hint, defaults.hintPosition, hint.Size, 0, 1)
				hint.Position, hint.Size = position, size
			end
		end
		if roll then
			-- «Таблетка» плавно меняет ширину и место (HINT_MORPH с), надпись «ударяет» на месте, 💡
			-- подпрыгивает (SIMB-C1-03: «слот-машина» двух надписей в «таблетке», уже сжатой под
			-- новый текст, вылезала за неё). Пока «таблетка» растёт — на ней старая надпись (новая
			-- длиннее: в узкую не влезла бы), сжимается — уже новая (она короче).
			local toSize, toPosition = hint.Size, hint.Position
			local wide = ui.fishing.AbsoluteSize.X
			local grows = toSize.X.Scale * wide + toSize.X.Offset > fromSize.X.Scale * wide + fromSize.X.Offset
			hint.Size, hint.Position = fromSize, fromPosition
			UiFx.tween(hint, HINT_MORPH, { Size = toSize, Position = toPosition })
			local shown: string = text
			local function swap()
				if hint.Text == shown and hint.Visible then
					ui.hintLabel.Text = shown
					UiFx.punch(ui.hintLabel, { from = 0.85 })
					UiFx.popIn(ui.hintSocket, { from = 0.6, time = 0.3, rotate = -12 })
				end
			end
			if grows then
				task.delay(HINT_MORPH, swap)
			else
				swap()
			end
		else
			ui.hintLabel.Text = text
		end
		ui.hintIcon.Text = icon
		UiFx.setCandy(hint, HINT_TOKENS[kind] or "Glass")
		hint.Visible = true
		if changed and not roll then
			animateHint(kind)
		end
	end

	-- Подсказка о событии: висит HINT_TIME секунд и прячется сама.
	function showHint(text: string, kind: string)
		if hintThread then
			task.cancel(hintThread)
		end
		eventHint = { text = text, kind = kind }
		renderHint(true)
		hintThread = task.delay(HINT_TIME, function()
			hintThread = nil
			eventHint = nil
			renderHint()
		end)
	end

	-- Убрать подсказку о событии сразу (поклёвка и мини-игра занимают её место в колонке).
	function clearEventHint()
		local thread = hintThread
		hintThread = nil
		if thread and thread ~= coroutine.running() and coroutine.status(thread) == "suspended" then
			task.cancel(thread)
		end
		if eventHint then
			eventHint = nil
			renderHint()
		end
	end

	-- Подсказка по месту: видна HINT_INFO_TIME с и уходит; again — навигационная (куда идти)
	-- возвращается через столько секунд, пока к месту. Новый текст — показывается заново.
	local function armContext()
		local thread = contextTimer
		contextTimer = nil
		if thread and thread ~= coroutine.running() and coroutine.status(thread) == "suspended" then
			task.cancel(thread)
		end
		if not contextHint then
			return
		end
		contextTimer = task.delay(if contextFaded then contextAgain or 0 else HINT_INFO_TIME, function()
			contextTimer = nil
			contextFaded = not contextFaded
			renderHint()
			if contextAgain or not contextFaded then
				armContext()
			end
		end)
	end

	function setContextHint(text: string?, again: number?)
		if contextHint == text then
			return
		end
		contextHint = text
		contextAgain = again
		contextFaded = false
		armContext()
		renderHint()
	end

	function destroyGuide()
		local current = guide
		guide = nil
		if current then
			current.beam:Destroy()
			current.from:Destroy()
			current.to:Destroy()
		end
	end

	-- Луч от персонажа к точке рыбалки (создаётся только на этом клиенте).
	local function createGuide(root: BasePart, spot: BasePart): Guide
		local from = Instance.new("Attachment")
		from.Name = "FishingGuideFrom"
		from.Parent = root
		local to = Instance.new("Attachment")
		to.Name = "FishingGuideTo"
		to.Position = Vector3.new(0, spot.Size.Y / 2 + 0.4, 0)
		to.Parent = spot

		local beam = Instance.new("Beam")
		beam.Name = "FishingGuide"
		beam.Attachment0 = from
		beam.Attachment1 = to
		beam.FaceCamera = true
		beam.Segments = 1
		beam.Width0 = 0.3
		beam.Width1 = 0.8
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Color = ColorSequence.new(COLORS.Guide)
		beam.Transparency = NumberSequence.new(0.55, 0.15)
		beam.Parent = root
		return { beam = beam, from = from, to = to, spot = spot }
	end

	function setGuide(spot: BasePart?)
		local root = rootPart()
		if not spot or not root then
			if guide then
				guide.beam.Enabled = false
			end
			return
		end
		local old = guide
		if old and (old.spot ~= spot or old.from.Parent ~= root) then
			destroyGuide() -- другая база или новый персонаж
		end
		local current = guide or createGuide(root, spot)
		guide = current
		current.beam.Enabled = true
	end

	--[[
		Виджет колонки (поклёвка, мини-игра) не закрывает своего поплавка и своего рыбака
		(FishingLayout): поплавок — от антенны до нырка на dive studs вниз, с запасом BOBBER_CLEAR px;
		рыбак — всё его тело с удочкой и рыбой над головой (на телефоне, если спроецировать не
		вышло, — где он стоит у камеры по умолчанию). dock (мини-игра на телефоне): виджет сразу
		встаёт СЛЕВА от рыбака (FishingLayout.dockLeft: напротив его середины, под плашками
		статуса, над джойстиком; не уже MinSize его UISizeConstraint); без dock (поклёвка,
		подсказка) — туда же, только если внизу он всё равно лёг бы на рыбака. Если виджет в покое (rest,
		restSize) что-то закрывает, он сначала становится ниже (не меньше minScale; низ — на
		месте), иначе отъезжает вбок — в просвет между джойстиком и кнопкой действия (у
		прижатого слева — между краем экрана и рыбаком). Места нет — всё как было. Возвращает
		позицию и размер для виджета и середину поплавка на экране (px корня; nil — не видно).
	]]
	-- Свой рыбак на экране (px HUD.Fishing, с запасом; FishingLayout.Rect): спроецированный, а на
	-- телефоне, если не вышло, — где он стоит у камеры по умолчанию; nil — не знаем (большой экран).
	function fisherRect(): any
		local root = ui.fishing
		local area = root.AbsoluteSize
		return Layout.fisherBox(player.Character, Workspace.CurrentCamera, root.AbsolutePosition)
			or (if area.Y < SHORT_SCREEN then Layout.fallbackFisher(area) else nil)
	end

	local BOBBER_CLEAR = 12
	local OUTLINE = 7 -- обводка и «аура» редкости (Sim.Stroke + 4: 6.5 px на телефоне) выступают за виджет, px
	local BITE_FLIGHT_SCALE = 0.35 -- «КЛЮЁТ!» вылетает из поплавка такой маленькой (enterBite)
	local fishingFx: any = nil -- FishingFxController (берётся при первом вызове), false — нет

	-- Верх полосы слева (px корня) для виджета, прижатого слева до x1: под видимыми плашками
	-- статуса над ним (с зазором COLUMN_GAP); низ — над джойстиком (тач-экран). edge — сколько
	-- его обводка и «аура» выступают за него (не меньше OUTLINE; на планшете толще). Ряд по
	-- центру (кошелёк Этапа 3: «💵 $0 +$4/с» в широкой рамке) мешает только своим содержимым.
	local function dockBand(origin: Vector2, height: number, x1: number, edge: number): (number, number)
		local top = 8 + edge
		for _, item in ui.status:GetChildren() do
			if item:IsA("GuiObject") and item.Visible then
				local at = item.AbsolutePosition - origin
				local left, right = at.X, at.X + item.AbsoluteSize.X
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
					width += math.max(count - 1, 0) * (row.Padding.Scale * item.AbsoluteSize.X + row.Padding.Offset)
					local middle = (left + right) / 2
					left, right = middle - width / 2, middle + width / 2
				end
				if left < x1 and right > Layout.EDGE then
					top = math.max(top, at.Y + item.AbsoluteSize.Y + Layout.EDGE + edge)
				end
			end
		end
		local bottom = height - Layout.EDGE - edge
		if UserInputService.TouchEnabled then
			local stick = if smallTouchScreen() then Layout.JUMP_SMALL else Layout.JUMP_BIG -- джойстик — зеркало прыжка
			bottom -= stick.bottom + stick.size
		end
		return top, bottom
	end

	function keepClearOfBobber(
		gui: GuiObject,
		rest: UDim2,
		restSize: UDim2,
		dive: number,
		minScale: number,
		dock: boolean?
	): (UDim2, UDim2, Vector2?)
		if fishingFx == nil then
			local module = script.Parent and script.Parent:FindFirstChild("FishingFxController")
			local ok, controller = pcall(function(): any
				return if module and module:IsA("ModuleScript") then require(module) :: any else nil
			end)
			fishingFx = if ok and controller then controller else false
		end
		local camera = Workspace.CurrentCamera
		local ok, found = pcall(function(): any
			return fishingFx and fishingFx.GetBobber(player)
		end)
		local bobber: Model? = if ok
				and typeof(found) == "Instance"
				and (found :: Instance):IsA("Model")
			then found :: Model
			else nil
		local root = ui.fishing
		local origin, area = root.AbsolutePosition, root.AbsoluteSize
		local short = area.Y < SHORT_SCREEN
		local keepouts: { Layout.Rect } = {}
		local float = Layout.bobberBox(bobber, camera, origin, dive, BOBBER_CLEAR)
		local at: Vector2? = nil
		if float then
			table.insert(keepouts, float)
			at = Vector2.new((float.x0 + float.x1) / 2, float.y0 + BOBBER_CLEAR)
		end
		local fisher = fisherRect()
		if fisher then
			table.insert(keepouts, fisher)
		end
		local box = boxSize(gui, area.X, area.Y, restSize)
		local cap = gui:FindFirstChildOfClass("UISizeConstraint")
		local narrowest = if cap and cap.MinSize.X > 0 then math.min(cap.MinSize.X, box.X) else box.X
		-- Место: внизу по центру (withDock — слева от рыбака), сдвинутое от поплавка и рыбака.
		local function place(withDock: boolean): Layout.Rect
			local placed = Layout.rectOf(rest, box, gui.AnchorPoint, area)
			local left, right = spanLeft, spanRight
			if withDock and fisher then
				local aura = gui:FindFirstChild("AuraStroke")
				-- (+1 px: сглаживание края «ауры» на экране)
				local edge =
					math.max(OUTLINE, if aura and aura:IsA("UIStroke") then UiFx.strokeThickness(aura) + 1 else 0)
				local top, bottom = dockBand(origin, area.Y, math.min(Layout.EDGE + box.X, fisher.x0), edge)
				-- (Виджет, которому можно стать меньше, — меньше целиком, не сплющенный.)
				local shrinks = minScale < 1
				local slot = Layout.dockLeft(
					fisher,
					box,
					if shrinks then math.min(narrowest, box.X * minScale) else narrowest,
					top,
					bottom,
					if shrinks then box.X / math.max(box.Y, 1) else nil
				)
				if slot then
					placed, left, right = slot, Layout.EDGE, fisher.x0
				end
			end
			return Layout.avoid(placed, keepouts, { left, right }, minScale, narrowest)
		end
		-- dock (мини-игра) на телефоне — сразу слева; на планшете и ПК мини-игра, а на телефоне
		-- поклёвка и подсказка — слева, только если внизу рыбака не обойти (камера рыбалки
		-- опускает его к низу кадра; UX-01: и на планшете ноги рыбака были под панелью).
		local docked = dock == true and short
		local moved = place(docked)
		if not docked and (dock or short) and fisher and Layout.hits(moved, fisher) then
			moved = place(true)
		end
		if at and fisher and Layout.flightHits(at, moved, fisher, BITE_FLIGHT_SCALE) then
			at = nil -- (из поплавка по пути плашка закрыла бы рыбака: тогда она «выскакивает» на месте)
		end
		local before = Layout.rectOf(rest, box, gui.AnchorPoint, area)
		if
			math.abs(moved.x0 - before.x0) < 0.5
			and math.abs(moved.x1 - before.x1) < 0.5
			and math.abs(moved.y0 - before.y0) < 0.5
			and math.abs(moved.y1 - before.y1) < 0.5
		then
			return rest, restSize, at -- не закрывает
		end
		local position, size = Layout.placeOf(moved, gui.AnchorPoint)
		return position, size, at
	end

	--[[
		«Удар» виджета колонки с большого (плашка «КЛЮЁТ!» на планшете и ПК, без полёта из поплавка):
		с какого масштаба (не больше from) он может начаться, вырастая вокруг своего якоря, чтобы и в
		начале — с обводкой (OUTLINE) — держать 16 px до ленты подписи кнопки действия на пике её
		«удара» смены вида (до 1.08, не больше GrowMax), до джойстика (тач-экран) и до своего рыбака
		(V-03: удар 1.6 на планшете ложился на «ПОДСЕЧЬ!»). position / size — виджет в покое; 1 — места
		на удар нет.
	]]
	function slamRoom(gui: GuiObject, position: UDim2, size: UDim2, from: number): number
		local root = ui.fishing.AbsoluteSize
		local plate = Layout.rectOf(position, boxSize(gui, root.X, root.Y, size), gui.AnchorPoint, root)
		plate = Layout.rect(plate.x0 - OUTLINE, plate.y0 - OUTLINE, plate.x1 + OUTLINE, plate.y1 + OUTLINE)
		local gap = Layout.RING.clear -- (16 px — как до кнопки прыжка)
		-- Кнопка действия: круг с якорем в центре (layoutColumn), лента подписи шире круга, её обводка
		-- — не толще OUTLINE.
		local area = ui.actionArea.AbsoluteSize
		local rest = defaults.actionPosition
		local ribbon = ui.actionButton:FindFirstChild("CaptionRibbon")
		local wide = if ribbon and ribbon:IsA("GuiObject") then math.max(ribbon.Size.X.Scale, 1) else 1
		local reach = defaults.actionSize.Y.Scale * area.Y / 2 * wide + OUTLINE
		local disc = ui.actionArea.AbsolutePosition.X
			- ui.fishing.AbsolutePosition.X
			+ rest.X.Scale * area.X
			+ rest.X.Offset
		local peak = math.min(1.08, (ui.actionButton:GetAttribute("GrowMax") :: number?) or 2)
		local keepouts = { Layout.rect(disc - reach * peak - gap, -math.huge, math.huge, math.huge) }
		if UserInputService.TouchEnabled then
			local small = smallTouchScreen() -- (джойстик: правый край STICK_*, верх в 90 / 210 px от низа)
			table.insert(
				keepouts,
				Layout.rect(
					-math.huge,
					root.Y - (if small then 90 else 210) - gap,
					(if small then STICK_SMALL else STICK_BIG) + gap,
					math.huge
				)
			)
		end
		local fisher = fisherRect()
		if fisher then
			table.insert(keepouts, fisher)
		end
		return Layout.growFrom(plate, gui.AnchorPoint, from, keepouts)
	end
end

--------------------------------------------------------------------------------
-- Кнопка действия и состояния рыбалки
--------------------------------------------------------------------------------

-- Наружу из раздела (блок do … end, см. «Устройство файла» в шапке):
local isFar, whiteRings, refreshButtons, refreshContextHint, pointToSpot, setPhase, startCastCooldown, endSession
local bindTakeKeys -- клавиши «ВЗЯТЬ» (1 / F / R2): ниже, рядом с остальным вводом (onActionInput)
do
	-- Подсказки по месту (только клиент). Куда идти — одним текстом везде: вдали от точки с
	-- удочкой в рюкзаке (и новичку сразу после появления) или в руке и в отказе сервера
	-- (FishingConfig.Texts.Denied.far). «Возьми удочку» — у самой точки: кнопка «ВЗЯТЬ» справа
	-- есть везде, где удочка в рюкзаке.
	local HINT_NEAR = "Жми «Забросить»"

	local HINT_FAR = TEXTS.Denied.far
	local HINT_TAKE = "Возьми удочку — кнопка справа"

	-- Удочка в рюкзаке (где угодно; есть база, персонаж жив): кнопка берёт удочку в руку.
	local TAKE_LOOK: Look = {
		Name = "Take",
		Caption = "ВЗЯТЬ",
		Icon = "🎣",
		Token = "Gold",
		Key = true,
		Ring = 0.15,
		RingColor = Palette.Gold.Top,
	}

	-- Удочка в руке, но до точки рыбалки далеко: кнопка не забрасывает, а показывает дорогу.
	local FAR_LOOK: Look = {
		Name = "Far",
		Caption = "КУДА ИДТИ?",
		Icon = "🧭",
		Token = "Slate",
		Key = false,
		Ring = 1,
		RingColor = WHITE,
	}

	-- Как выглядит кнопка действия в каждом состоянии.
	local LOOKS: { [Phase]: Look } = {
		Idle = CAST_LOOK,
		Pending = WAIT_LOOK,
		Waiting = WATER_LOOK,
		Bite = BITE_LOOK,
		Reeling = REEL_LOOK,
	}

	-- Улов на экране (FUI-09): от "Caught", пока доли карточки не показаны, и пока 🐟 летит в
	-- счётчик, кнопка «замирает» — тусклая, без песочных часов, колец и «выскоков» (нажатия
	-- ничего не делают: пропускает доли только тап по самой карточке).
	local CATCH_LOOK: Look = {
		Name = "Catch",
		Caption = "ЖДЁМ…",
		Icon = "⏳",
		Token = "Slate",
		Key = false,
		Ring = 1,
		RingColor = WHITE,
	}
	-- Карточка показана целиком (тап её закроет — «Тапни — забрать!»): кнопка зовёт забрать
	-- улов — зелёная, белые кольца; нажатие закрывает карточку уже нарочно (после паузы —
	-- CARD.Mash: «ЛОВИ!», которую ещё жмут по инерции, её не прячет).
	local COLLECT_LOOK: Look = {
		Name = "Collect",
		Caption = "ЗАБРАТЬ!",
		Icon = "👍",
		Token = "Leaf",
		Key = true,
		Ring = 0.15,
		RingColor = WHITE,
		Flash = true,
	}

	local cooldownThread: thread? = nil -- вернёт кнопке вид «ЗАБРОСИТЬ», когда кулдаун пройдёт
	local shownLook: Look? = nil -- вид кнопки, который сейчас нарисован
	local lookTrove = Trove.new() -- «фон» текущего вида кнопки (блик, песочные часы, сияние)

	-- Удочка в руке, леска не в воде, а до точки рыбалки своей базы далеко (допуск сервера, чуть
	-- строже — isNearSpot): кнопка «КУДА ИДТИ?» не забрасывает. Без базы — «ЗАБРОСИТЬ» (сервер
	-- объяснит отказ).
	function isFar(): boolean
		if not rod or phase ~= "Idle" then
			return false
		end
		local root = rootPart()
		local spot = ownFishingSpot()
		return root ~= nil and spot ~= nil and not isNearSpot(root, spot)
	end

	-- Рыба на крючке (поклёвка или мини-игра): «СМОТАТЬ» в это время нет.
	local function fishOn(): boolean
		return phase == "Bite" or phase == "Reeling"
	end

	local function currentLook(): Look
		if not rod then
			return TAKE_LOOK
		elseif phase == "Bite" and hookSent then
			return WAIT_LOOK -- подсечка отправлена, ждём мини-игру
		elseif phase == "Idle" and os.clock() < castReadyAt then
			return WAIT_LOOK -- сервер ещё не примет заброс (CastCooldown)
		elseif isFar() then
			return FAR_LOOK
		end
		return LOOKS[phase]
	end

	local BREATHE_PEAK, BREATHE_PERIOD = 1.05, 1.4 -- «дыхание» главной кнопки в покое (≈ 2 px к краям)
	local WATER_DOTS = { "ЖДИ КЛЁВА…", "ЖДИ КЛЁВА.", "ЖДИ КЛЁВА.." } -- бегущие точки ожидания (по 0.4 с)
	local WATER_SMALL = 0.85 -- кнопка ожидания поклёвки меньше (её жать не нужно), доля размера
	local WATER_DOTS_STEP = 0.4
	local BOBBER_BOB = 0.06 -- поплавок на кнопке качается на столько (доля кнопки) …
	local BOBBER_PERIOD = 1.2 -- … за столько секунд туда-обратно

	-- Белые кольца от кнопки (ВЗЯТЬ, ЛОВИ!, такт поклёвки): тонкий чёткий контур, 1 → 1.3 —
	-- читается на дереве, воде и небе. На тач-экране кольца растут вместе с пульсом кнопки (они —
	-- её дети) и не дотягиваются до кнопки прыжка: и на пике пульса (GrowMax) до неё остаются
	-- 16 px (FishingLayout.RING; круг для этого отодвинут — layoutColumn: на планшете кольцо
	-- вырастает до ≈ 1.2). once — одно кольцо (рябь от касания, кнопка вернулась после улова).
	function whiteRings(interval: number, once: boolean?): UiFx.Stop
		local grow, thickness = 1.3, 5 -- рост кольца; толщина, px (как FishingLayout.RING)
		local peak = math.min(1.14, (ui.actionButton:GetAttribute("GrowMax") :: number?) or 1.14) -- пик пульса поклёвки
		if UserInputService.TouchEnabled then
			local Layout = require(script.Parent:WaitForChild("FishingLayout")) :: any
			local clear = Layout.RING.clear
			local area = ui.actionArea.AbsoluteSize
			local rest = defaults.actionPosition
			local center = ui.actionArea.AbsolutePosition
				- ui.fishing.AbsolutePosition
				+ Vector2.new(rest.X.Scale * area.X + rest.X.Offset, rest.Y.Scale * area.Y + rest.Y.Offset)
			local camera = Workspace.CurrentCamera
			local view = if camera then camera.ViewportSize else Vector2.new(1280, 720)
			local room = Layout.growRoom(center, ui.fishing.AbsoluteSize, math.min(view.X, view.Y) <= 500, clear)
			local px = thickness * math.clamp(view.Y / 720, 0.65, UIConfig.Fx.StrokeMax) -- (как fitStrokes)
			local radius = math.max(defaults.actionSize.Y.Scale * area.Y / 2, 1)
			grow = math.clamp((room / peak - px) / radius, 1, grow) -- (места нет — кольцо под обводкой)
		end
		return UiFx.glowRing(ui.actionButton, {
			loop = not once,
			color = WHITE,
			scale = if once then math.min(grow, 1.35) else grow,
			thickness = if once then 3 else thickness,
			time = if once then 0.45 else 0.6,
			interval = interval,
		})
	end

	-- «Фон» вида кнопки: только таймеры и твины (без покадровых соединений).
	local function startLookFx(look: Look)
		lookTrove:Clean()
		local button = ui.actionButton
		local icon = ui.actionIcon
		icon.Rotation = defaults.iconRotation
		-- Красный кружок «!» (как у «Магазина» образца) зовёт новичка: на «ВЗЯТЬ» и «ЗАБРОСИТЬ», пока
		-- за сессию не было ни одного заброса (атрибут Casted: фаза уже была не Idle); качается
		-- раз в 3 с (UiFx.badgeBob — таймеры). При смене «ВЗЯТЬ» → «ЗАБРОСИТЬ» не мигает; прячется,
		-- когда вид уже другой.
		if phase ~= "Idle" then
			button:SetAttribute("Casted", true) -- леска уже была в воде (заброс принят)
		end
		local badge = button:FindFirstChild("Badge")
		if badge and badge:IsA("GuiObject") then
			if (look == CAST_LOOK or look == TAKE_LOOK) and not button:GetAttribute("Casted") then
				if not badge.Visible then
					UiFx.badgeBob(badge)
				end
			elseif badge.Visible then
				UiFx.badgeHide(badge)
			end
		end
		if look == CAST_LOOK or look == TAKE_LOOK or look == COLLECT_LOOK then
			-- Главная кнопка «дышит» (вдох-выдох — один твин за такт, только в покое: нажатие его
			-- прерывает), блестит, а её значок раз в ≈ 3 с качается с «вдохом» — не в такт блику.
			-- Больше в покое на экране ничего не шевелится. («ЗАБРАТЬ!» — только дышит, с кольцами.)
			-- (Кнопка растёт от своей середины: не больше чем на 4 px с каждой стороны — к кнопке
			-- прыжка.)
			local side = button.AbsoluteSize.X
			local peak = if side > 1 then 1 + math.min(BREATHE_PEAK - 1, 8 / side) else BREATHE_PEAK
			lookTrove:Add(UiFx.breathe(button, { peak = peak, period = BREATHE_PERIOD }))
			if look ~= COLLECT_LOOK then
				lookTrove:Add(UiFx.wobbleLoop(icon, { angle = if look == TAKE_LOOK then 14 else 10, bump = 1.1 }))
			end
		end
		if look == CAST_LOOK then
			lookTrove:Add(UiFx.shineLoop(button, { interval = UIConfig.Fx.ShineInterval, delay = 1.7 }))
		elseif look == TAKE_LOOK then
			lookTrove:Add(UiFx.shineLoop(button, { interval = 2.4, delay = 0.6 }))
			lookTrove:Add(whiteRings(1.0))
		elseif look == WAIT_LOOK then
			-- Песочные часы переворачиваются.
			local turns = 0
			local flip: Tween? = nil
			every(lookTrove, 1.1, function()
				turns += 1
				flip = UiFx.tween(
					icon,
					0.45,
					{ Rotation = defaults.iconRotation + 180 * turns },
					Enum.EasingStyle.Back,
					Enum.EasingDirection.Out
				)
			end, 0.55)
			lookTrove:Add(function()
				if flip then
					flip:Cancel()
				end
				icon.Rotation = defaults.iconRotation
			end)
		elseif look == WATER_LOOK then
			-- Кнопка становится меньше (вокруг своей середины: якорь в центре), поплавок качается на
			-- «воде» кнопки, точки бегут; «примерка» рыбы — вздрагивание и «?» (nibble). Кругов нет:
			-- ничего не зовёт.
			local restSize = defaults.actionSize
			UiFx.tween(button, 0.25, {
				Size = UDim2.fromScale(restSize.X.Scale * WATER_SMALL, restSize.Y.Scale * WATER_SMALL),
			}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			lookTrove:Add(function()
				UiFx.tween(button, 0.2, { Size = defaults.actionSize }) -- (экран мог смениться)
			end)
			-- Надпись длиннее «ЗАБРОСИТЬ», а кнопка меньше: надпись и плашка подписи остаются
			-- прежней ширины в px, а надпись может стать мельче — до уровня Small (в одну строку).
			local ribbon = button:FindFirstChild("CaptionRibbon")
			local keep: { [GuiObject]: UDim2 } = { [ui.actionCaption] = defaults.captionSize }
			if ribbon and ribbon:IsA("GuiObject") then
				keep[ribbon] = defaults.ribbonSize
			end
			for gui, size in keep do
				local wide =
					UDim2.new(size.X.Scale / WATER_SMALL, size.X.Offset, size.Y.Scale / WATER_SMALL, size.Y.Offset)
				UiFx.tween(gui, 0.25, { Size = wide }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				lookTrove:Add(function()
					UiFx.tween(gui, 0.2, { Size = size })
				end)
			end
			local fit = ui.actionCaption:FindFirstChildOfClass("UITextSizeConstraint")
			if fit then
				local min = fit.MinTextSize
				fit.MinTextSize = math.min(min, UiFx.textSize("Small"))
				lookTrove:Add(function()
					fit.MinTextSize = min
				end)
			end
			local bobber = ui.actionBobber
			local rest = defaults.bobberPosition
			bobber.Position = rest - UDim2.fromScale(0, BOBBER_BOB / 2)
			local bob = TweenService:Create(
				bobber,
				TweenInfo.new(BOBBER_PERIOD / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Position = rest + UDim2.fromScale(0, BOBBER_BOB / 2) }
			)
			bob:Play()
			lookTrove:Add(function()
				bob:Cancel()
				bobber.Position = rest
			end)
			local step = 0
			every(lookTrove, WATER_DOTS_STEP, function()
				step = step % #WATER_DOTS + 1
				ui.actionCaption.Text = WATER_DOTS[step]
			end)
			-- Плашка ожидания чуть покачивается (поворот ±1.5°, один бесконечный твин): «на волне».
			lookTrove:Add(UiFx.sway(button))
		elseif look == REEL_LOOK or look == COLLECT_LOOK then
			lookTrove:Add(whiteRings(1.1))
		end
		-- BITE_LOOK: пульс и кольца в такт — в actionPulseTrove (enterBite), до подсечки.
		-- FAR_LOOK: спокойная серая кнопка (без блика и колец).
	end

	-- Перекрасить кнопку под вид; animate — смена состояния на виду: цвета и обводка перетекают
	-- (UiFx.recolor), кнопка «ударяет» (0.86 → 1.08 → 1, вокруг своей середины), значок влетает с
	-- оборотом, надпись «ударяет» (refreshButtons); у важных видов («ПОДСЕЧЬ!»,
	-- «ЛОВИ!», «ЗАБРАТЬ!») — ещё белая вспышка «превращения» и свист.
	local function applyLook(look: Look, animate: boolean)
		local button = ui.actionButton
		if animate then
			UiFx.recolor(button, look.Token)
		else
			UiFx.setCandy(button, look.Token)
		end
		ui.actionIcon.Text = look.Icon
		-- Обводка у значка всегда (тёмный контур эмодзи, как в образце); у знака «!» (белый →
		-- золотой) она толще. Выключать её нельзя: другой обводки у значка нет.
		ui.actionOutline:SetAttribute("BaseThickness", if look.Glyph then 5 else 3.5)
		ui.actionOutline.Thickness = UiFx.strokeThickness(ui.actionOutline)
		ui.actionFill.Enabled = look.Glyph == true
		ui.actionBobber.Visible = look.Bobber == true
		ui.actionRing.Color = look.RingColor
		ui.actionRing.Transparency = look.Ring
		startLookFx(look)
		if animate then
			UiFx.punch(button, { from = 0.86, peak = math.min(1.08, (button:GetAttribute("GrowMax") :: number?) or 2) })
			if look.Bobber then
				UiFx.popIn(ui.actionBobber, { from = 0.2, time = 0.34, delay = 0.04 })
			else
				UiFx.popIn(ui.actionIcon, { from = 0.2, time = 0.32, delay = 0.04, rotate = -120 })
			end
			if look.Flash then
				UiFx.morphFlash(button)
				UiFx.sound("swoosh", 0.3, 1.4)
			end
		end
	end

	function refreshButtons()
		local collect = catchScreen and cardSettled and ui.card.Visible
		local look = if collect then COLLECT_LOOK elseif catchScreen then CATCH_LOOK else currentLook()
		local button = ui.actionButton
		local wasVisible = button.Visible
		local visible = rod ~= nil or offerTake
		button.Visible = visible
		-- Клавиша действия (F / R2) — на «клавише» у плеча кнопки, когда действие ею доступно; она
		-- «ударяет», появляясь.
		local key = look.Key and keyHint ~= ""
		if key and not ui.keyChip.Visible and visible and wasVisible then
			UiFx.punch(ui.keyChip, { from = 0.6, peak = 1.12 })
		end
		ui.keyChip.Visible = key
		ui.keyLabel.Text = keyHint
		if look ~= shownLook then
			local first = shownLook == nil
			local animate = visible and wasVisible and not first and look ~= CATCH_LOOK
			shownLook = look
			-- (Новая надпись «ударяет» на своём месте: прокрутка двух надписей на узкой «таблетке»
			-- читалась бы кашей. Следом за кнопкой, когда та уже почти на месте: оба перелёта разом
			-- дотянули бы конец надписи до кнопки прыжка.)
			ui.actionCaption.Text = look.Caption
			if animate then
				UiFx.punch(ui.actionCaption, { from = 0.7, peak = 1.1, delay = 0.12 })
			end
			applyLook(look, animate)
		elseif look ~= WATER_LOOK then
			ui.actionCaption.Text = look.Caption -- (бегущие точки ожидания пишет сам вид)
		end
		if visible and not wasVisible then
			-- Кнопка появилась (удочка в руке / «ВЗЯТЬ»): выскакивает с доворотом.
			UiFx.popIn(button, { from = 0.3, time = 0.4, rotate = -12 })
			UiFx.popIn(ui.actionIcon, { from = 0, time = 0.4, delay = 0.12, rotate = -30 })
		end
		-- «СМОТАТЬ» — пока леска в воде и рыбы на крючке нет: в поклёвку и мини-игру её нет
		-- (тап мимо «ЛОВИ!» не должен стоить рыбы). Уходит быстро, сжимаясь.
		-- Появляясь, она выскакивает из своего правого нижнего угла (её якорь: к «ДОМОЙ» перелёт не
		-- растёт), 🎣 влетает с оборотом, надпись «ударяет», ободок вспыхивает.
		local stop = ui.stopButton
		local stopVisible = rod ~= nil and isLineOut() and not fishOn()
		if stopVisible and not stop.Visible then
			stop.Visible = true
			UiFx.popIn(stop, { from = 0.2, time = 0.35, delay = 0.05 })
			local stopIcon = stop:FindFirstChild("Icon")
			if stopIcon and stopIcon:IsA("GuiObject") then
				UiFx.popIn(stopIcon, { from = 0, time = 0.35, delay = 0.12, rotate = -180 })
			end
			UiFx.punch(ui.stopCaption, { from = 0.6, peak = 1.1, delay = 0.08 })
			UiFx.rimFlash(stop, { delay = 0.22 })
		elseif not stopVisible and stop.Visible then
			if fishOn() and button.Visible then
				UiFx.popOut(stop, { time = 0.2, to = 0.3, hide = true }) -- «вдох» и прочь
			else
				stop.Visible = false
			end
		end
	end

	-- Подсказка по месту: удочка в руке или в рюкзаке, без рыбалки, а до точки далеко — «иди к
	-- кругу» + луч (и сразу после появления: игрок стоит на базе, круг — на краю пирса); у точки
	-- с удочкой в руке — «жми», с удочкой в рюкзаке — «возьми удочку». Удочка в рюкзаке (есть база,
	-- персонаж жив) — кнопка «ВЗЯТЬ» где угодно: экран никогда не предлагает одну «ДОМОЙ». Ушёл
	-- от точки / вернулся — кнопка с удочкой в руке меняется между «ЗАБРОСИТЬ» и «КУДА ИДТИ?».
	-- WOW-6: подсказка-обучалка («жми», «возьми», «иди к кругу») больше не показывается, когда
	-- игрок сделал это сам HINT_LEARNED раз за игру (подсказка стояла — и её дело сделано:
	-- заброс, удочка в руке, пришёл к кругу); навигационная (куда идти) до тех пор возвращается
	-- раз в HINT_AGAIN с. Предупреждения (далеко, поздно, ждём базу) — как были.
	local HINT_LEARNED = 2
	local HINT_AGAIN = 10
	local learned: { [string]: number } = {}
	local shownFar = false
	local lastContext: string? = nil
	function refreshContextHint()
		local text: string? = nil
		local guideTo: BasePart? = nil
		local root = rootPart()
		local spot = ownFishingSpot()
		local near = root ~= nil and spot ~= nil and isNearSpot(root, spot)
		local take = rod == nil and phase == "Idle" and hasBase() and isAlive() and backpackRod() ~= nil
		local far = isFar()
		if take ~= offerTake or far ~= shownFar then
			if take ~= offerTake then
				bindTakeKeys(take)
			end
			offerTake = take
			shownFar = far
			refreshButtons()
		end
		-- Луч к кругу — удочка в руке или «ВЗЯТЬ», без рыбалки и экрана улова, а до точки далеко.
		-- Он в мире и рыбака не закрывает: горит и пока своя рыба над головой («ДОМОЙ» сразу после
		-- улова — луч уже ведёт назад).
		local idle = take or (rod ~= nil and phase == "Idle")
		if idle and root and spot and not near and not catchScreen then
			guideTo = spot
		end
		-- Текст ждёт. v3: на телефоне (HUD ниже 500 px), пока своя рыба над головой: рыбак с
		-- трофеем опускается к низу кадра (камера трофея) — плитка легла бы ему на ноги. И пока по
		-- центру стоит баннер «ТВОЯ БАЗА» (вход в игру, HudController): под ним первая «куда идти»
		-- отвисела бы свои HINT_INFO_TIME почти не прочитанной — она выскакивает целиком, когда
		-- баннер улетел в плашку (следующий опрос, CONTEXT_CHECK_INTERVAL).
		local character = player.Character
		local trophy = character ~= nil
			and character:FindFirstChild("HeldFish") ~= nil
			and ui.fishing.AbsoluteSize.Y < 500
		local welcome = ui.baseBanner ~= nil and ui.baseBanner.Visible
		if not catchScreen and not trophy and not welcome then
			if guideTo then
				text = HINT_FAR
			elseif rod and idle and root and spot then
				text = HINT_NEAR
			elseif take then
				text = HINT_TAKE
			end
		end
		-- Сделал то, о чём говорила подсказка: забросил, взял удочку, дошёл до круга.
		local done = (lastContext == HINT_NEAR and phase ~= "Idle")
			or (lastContext == HINT_TAKE and rod ~= nil)
			or (lastContext == HINT_FAR and near)
		if done and lastContext then
			learned[lastContext] = (learned[lastContext] or 0) + 1
		end
		lastContext = text
		setGuide(guideTo)
		if text and (learned[text] or 0) >= HINT_LEARNED then
			text = nil
		end
		setContextHint(text, if text == HINT_FAR then HINT_AGAIN else nil)
	end

	-- «КУДА ИДТИ?» нажата: вместо заброса — показать дорогу, не ругая (спокойная подсказка 💡
	-- выскакивает заново, компас на кнопке делает оборот «ищу север», луч к точке рыбалки на
	-- миг становится толще и ярче). Сам персонаж никуда не идёт. Частые нажатия (тап за тапом)
	-- не перезапускают это чаще раза в POINT_GAP секунд.
	local POINT_GAP = 0.8
	local pointedAt = -math.huge
	function pointToSpot()
		local now = os.clock()
		if now - pointedAt < POINT_GAP then
			return
		end
		pointedAt = now
		showHint(HINT_FAR, "info")
		local icon = ui.actionIcon
		icon.Rotation = defaults.iconRotation
		UiFx.tween(
			icon,
			0.55,
			{ Rotation = defaults.iconRotation + 360 },
			Enum.EasingStyle.Back,
			Enum.EasingDirection.Out
		)
		task.delay(0.6, function()
			if shownLook == FAR_LOOK then
				icon.Rotation = defaults.iconRotation
			end
		end)
		UiFx.sound("ping", 0.3, 1.5)
		local current = guide
		if current and current.beam.Enabled then
			local beam = current.beam
			beam.Width0, beam.Width1 = 0.7, 2.2
			beam.Transparency = NumberSequence.new(0.2, 0)
			UiFx.tween(beam, 0.6, { Width0 = 0.3, Width1 = 0.8 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			task.delay(0.6, function()
				if beam.Parent then
					beam.Transparency = NumberSequence.new(0.55, 0.15)
				end
			end)
		end
	end

	local function cancelPending()
		local thread = pendingThread
		pendingThread = nil
		if thread and thread ~= coroutine.running() then
			task.cancel(thread)
		end
	end

	-- Новое состояние: убираем анимации и окна прошлого, обновляем кнопки. Плашка «КЛЮЁТ!» уходит
	-- копией (FxBiteOut; сама прячется сразу): подсекли (дальше мини-игра) — «вдох», сжатие и
	-- белое кольцо; не успели — сползает вниз и тает («ушла»).
	function setPhase(newPhase: Phase)
		cancelPending()
		local alert = ui.biteAlert
		if alert.Visible and phase == "Bite" and newPhase ~= "Bite" then
			local ghost = ghostOf(alert, "FxBiteOut")
			if newPhase == "Reeling" then
				-- (Под мини-игрой: та встаёт в тот же слот — копия не закрывает её полосу и заголовок.)
				ghost.ZIndex = ui.minigame.ZIndex - 1
				UiFx.glowRing(ghost, { color = WHITE, scale = 1.25, thickness = 4, time = 0.2 })
				UiFx.popOut(ghost, { time = 0.14, destroy = true })
			else
				local quad, inDir = Enum.EasingStyle.Quad, Enum.EasingDirection.In
				UiFx.tween(ghost, 0.22, { Position = ghost.Position + UDim2.fromOffset(0, 10) }, quad, inDir)
				UiFx.fadeOut(ghost, 0.22)
				task.delay(0.23, function()
					ghost:Destroy()
				end)
			end
		end
		phaseTrove:Clean()
		actionPulseTrove:Clean()
		phase = newPhase
		if newPhase ~= "Reeling" then
			minigame = nil
		end
		alert.Visible = false
		ui.minigame.Visible = false
		-- (Сначала — предлагать ли «ВЗЯТЬ»: убранная удочка перетекает из «ЗАБРОСИТЬ» в «ВЗЯТЬ»,
		-- а не прячет кнопку на миг, чтобы та выскочила снова.)
		refreshContextHint()
		refreshButtons()
	end

	-- Сервер не примет новый заброс ещё CastCooldown секунд — кнопка до тех пор тусклая.
	function startCastCooldown()
		castReadyAt = os.clock() + FishingConfig.CastCooldown
		local previous = cooldownThread
		if previous and coroutine.status(previous) == "suspended" then
			task.cancel(previous)
		end
		cooldownThread = task.delay(FishingConfig.CastCooldown, function()
			cooldownThread = nil
			castReadyAt = 0 -- таймер может сработать на долю микросекунды «раньше» os.clock()
			refreshButtons()
		end)
	end

	-- Конец рыбалки (кулдаун заброса — только если леска была в воде).
	function endSession()
		local cooldown = isLineOut() or phase == "Pending"
		hookSent = false
		setPhase("Idle")
		if cooldown then
			startCastCooldown()
			refreshButtons()
		end
	end
end

--------------------------------------------------------------------------------
-- Улов: победа в мини-игре, прыжок рыбы, карточка (UI v2: FUI-01…04, 07, 09, 10, 12, 18)
--------------------------------------------------------------------------------

-- Насколько «громко» встречают рыбу: чем реже, тем больше всего (FUI-03).
type Reveal = {
	Id: string, -- редкость (её цвета — UIConfig.Rarity[Id])
	Dim: number, -- прозрачность затемнения (1 — без затемнения)
	Rays: number, -- лучей (на тач-экране — TouchRays)
	TouchRays: number,
	Speed: number, -- их вращение, °/с
	Size: number, -- диаметр лучей в высотах карточки
	MaxPx: number, -- … но не больше стольких пикселей на тач-экране (заливка на телефоне; на
	-- маленьком телефоне — меньше вместе с карточкой, на компьютере — CARD.DesktopRays × MaxPx)
	Alpha: number, -- прозрачность лучей
	Extra: boolean, -- второе кольцо лучей (вращается навстречу)
	Glow: number, -- маленьких лучей за рыбой на карточке
	Rim: number, -- «живая» обводка карточки в цветах редкости (во сколько раз толще; 0 — нет)
	Confetti: number, -- конфетти при приземлении
	ConfettiMid: number, -- мифическая: ещё залп через CARD.ConfettiMid с после приземления
	Confetti2: number, -- залп, когда цена «приземлилась» (с мутацией — после пересчёта)
	Coins: number, -- дождь 💰 тогда же (по бокам от карточки)
	Float: number, -- «+$4/с» из цены: высота в долях экрана (0 — нет)
	Sparkles: number, -- звёздочек вокруг рыбы в секунду
	Beat: number, -- доли карточки — не ближе этого друг к другу, с
	Count: number, -- сколько секунд набегает цена
	Hold: number, -- от приземления до карточки, с (у слова редкости — пока оно сложится и постоит)
	Scale: number, -- размер карточки (обычная рыба — поменьше, легендарная и мифическая — больше)
	Tension: boolean, -- виньетка по краям во время прыжка
	Heartbeat: boolean, -- «сердце» во время прыжка
	Title: boolean, -- огромное слово редкости
	Letters: boolean, -- … по буквам, волной
	Flash: Color3?, -- «громкое» приземление (легендарная и мифическая): звук ниже и свист; на весь
	-- экран — ничего (v3: и края не вспыхивают): главное — удар в точке рыбы, его должно быть видно
	Shake: boolean, -- лёгкая тряска камеры при приземлении
	Fov: number, -- «толчок» поля зрения при приземлении, ° (перед ним камера чуть «отъезжает»)
	Burst: number, -- удар в точке рыбы при приземлении: кольцо расходится до стольких высот экрана
	Trail: number, -- ✨ за летящей в счётчик 🐟
}

-- Где что на широкой карточке (доли карточки): рыба слева, справа столбик — имя, вес, цена,
-- подсказка; баннер во всю ширину сверху, «НОВИНКА!» и мутация — штампы на углах рыбы.
type Place = {
	Position: UDim2,
	Size: UDim2,
	AnchorPoint: Vector2,
	Rotation: number,
	SizeConstraint: Enum.SizeConstraint,
}

-- Наружу из раздела (блок do … end, см. «Устройство файла» в шапке):
local minigameShownAt = -math.huge
local cardReveal: Reveal
local cardTank: any = nil -- Этап 3: TankResult улова на экране (штамп, «+$/с», куда летит; nil — нет)
local offset, placeCard, winGhost, tapCard, beginCatch, onOwnFishLanded, parseFish
do
	--[[
		Порядок (c — момент, когда карточка открылась):
		  победный тап  стрелка мини-игры «замирает» золотой там, где тапнули (holdWin), до ответа
		               сервера (не дольше 1.5 с).
		  "Caught"     панель мини-игры «побеждает» (FxMinigameWin: ⭐, золотая зона, стрелка на месте
		               тапа, искры) и уходит вниз; левее персонажа «впечатывается» «ПОЙМАНА!» цвета
		               редкости с кольцом (тает за CLIMAX.WinTime — до приземления); кнопка
		               «замирает» (CATCH_LOOK), подсказки нет, бейдж и счётчик гаснут (счётчик держит
		               прошлое число — атрибут HUD CounterHold); у эпической и выше по краям нарастает
		               узкая рамка (CLIMAX.Tension), у легендарной и мифической — ускоряющееся
		               «сердце» и камера чуть «отходит» перед приземлением.
		  приземление  рыба долетела до места над головой (FishingFxController.OwnFishLanded; нет
		               сигнала — через LeapTime + 0.3 с): рамка обрывается, тонкое кольцо (CLIMAX.Shock)
		               и искры из точки рыбы (без свечения и вспышки краёв), тряска, «толчок» камеры,
		               конфетти; у эпической и выше через CLIMAX.TitleDelay — лучи из точки рыбы
		               (середина пустая, рыбу видно) и огромное слово редкости (буквы волной, блик),
		               через CLIMAX.TitleDim.At — лёгкое затемнение всего экрана.
		  + Hold       карточка рождается в точке рыбы и встаёт на место; затемнение (после слова —
		               темнее, «дырка» под карточкой открывается, когда она её закрыла), лучи
		               переезжают за карточку.
		  c+0 имя рождается с карточкой (въезжает справа), слово редкости влетает в баннер,
		  c+0.26 баннер вырастает из него (без слова — c+0.18 баннер «раскатывается»), +B
		  «НОВИНКА!», +B вес и цена, +0.12 цена набегает (REVEAL.Count, до самого конца) и
		  «приземляется», ещё через 0.12 с из фишки вылетает «+$4/с»; у мутации +B штамп, «×N»,
		  пересчёт, +0.67 полная цена; +B последняя доля — «Тапни — забрать!», кнопка «ЗАБРАТЬ!»,
		  лучи и рыба успокаиваются. B = REVEAL.Beat: обычная и редкая — 0.2 с (их ловят
		  десятками: от тапа до «+1» быстро), эпическая и выше — 0.27 с (тест «catch card beats»).
		  Новый вид обычной и редкой (CARD.New) — у «НОВИНКИ!» искры, конфетти и «дзынь».
		Тап по карточке до последней доли — сразу всё показать, следующий тап не раньше
		CLIMAX.SkipDwell — закрыть. Кнопка действия (F / R2, удочка) долей не пропускает: она
		закрывает только показанную целиком карточку и только через CARD.Mash после прошлого
		нажатия (пока жмут по инерции — нет).
		Закрытие: карточка сама — снаряд: летит в счётчик (первый улов — он появляется с «Улов:
		0»; цель — его место в списке Status, даже пока он не показан), сжимаясь почти в точку;
		через CARD.Fly рядом с ней вылетают 🐟 и ★ цветов редкости, все долетают вместе — счётчик
		+1 в цвете редкости (CounterHold и CounterIncoming сняты; от тапа ≈ 0.35 с), кнопка
		«оживает» видом «ЗАБРОСИТЬ», ещё через CLIMAX.Trophy рыба над головой ещё раз
		«вспыхивает» (FishingFxController.ReplayOwnTrophy: выскакивает своя табличка) и висит ещё
		≈3 с.
	]]

	local REVEAL: { [string]: Reveal } = {
		Common = {
			Id = "Common",
			Dim = 1,
			Rays = 8,
			TouchRays = 8,
			Speed = 12,
			Size = 1.7,
			MaxPx = 400,
			Alpha = 0.6,
			Extra = false,
			Glow = 6,
			Rim = 0,
			Confetti = 0,
			ConfettiMid = 0,
			Confetti2 = 0,
			Coins = 0,
			Float = 0,
			Sparkles = 1.5,
			Beat = 0.2,
			Count = 0.35,
			Hold = 0.35,
			Scale = 0.85,
			Tension = false,
			Heartbeat = false,
			Title = false,
			Letters = false,
			Flash = nil,
			Shake = false,
			Fov = 0,
			Burst = 0.6,
			Trail = 4,
		},
		Rare = {
			Id = "Rare",
			Dim = 0.6,
			Rays = 10,
			TouchRays = 8,
			Speed = 16,
			Size = 1.95,
			MaxPx = 500,
			Alpha = 0.36,
			Extra = false,
			Glow = 6,
			Rim = 0,
			Confetti = 12,
			ConfettiMid = 0,
			Confetti2 = 0,
			Coins = 0,
			Float = 0.11,
			Sparkles = 1.5,
			Beat = 0.2,
			Count = 0.45,
			Hold = 0.4,
			Scale = 1,
			Tension = false,
			Heartbeat = false,
			Title = false,
			Letters = false,
			Flash = nil,
			Shake = false,
			Fov = 0,
			Burst = 0.8,
			Trail = 5,
		},
		Epic = {
			Id = "Epic",
			Dim = 0.45,
			Rays = 12,
			TouchRays = 10,
			Speed = 20,
			Size = 2.15,
			MaxPx = 520,
			Alpha = 0.3,
			Extra = false,
			Glow = 8,
			Rim = 1.8,
			Confetti = 20,
			ConfettiMid = 0,
			Confetti2 = 0,
			Coins = 0,
			Float = 0.11,
			Sparkles = 2,
			Beat = 0.27,
			Count = 0.55,
			Hold = 1.2, -- v3: +0.6 с — руки вверх с рыбой над головой видно до карточки
			Scale = 1,
			Tension = true,
			Heartbeat = false,
			Title = true,
			Letters = false,
			Flash = nil,
			Shake = false,
			Fov = -3,
			Burst = 1,
			Trail = 6,
		},
		Legendary = {
			Id = "Legendary",
			Dim = 0.35,
			Rays = 14,
			TouchRays = 10,
			Speed = 24,
			Size = 2.35,
			MaxPx = 480,
			Alpha = 0.3,
			Extra = true,
			Glow = 8,
			Rim = 2.2,
			Confetti = 26,
			ConfettiMid = 0,
			Confetti2 = 12,
			Coins = 10,
			Float = 0.15,
			Sparkles = 2,
			Beat = 0.27,
			Count = 0.65,
			Hold = 1.5, -- v3: +0.6 с — руки вверх с рыбой над головой видно до карточки
			Scale = 1.05,
			Tension = true,
			Heartbeat = true,
			Title = true,
			Letters = true,
			Flash = Palette.Gold.Top,
			Shake = true,
			Fov = -6,
			Burst = 1.3,
			Trail = 7,
		},
		Mythic = {
			Id = "Mythic",
			Dim = 0.25,
			Rays = 16,
			TouchRays = 10,
			Speed = 28,
			Size = 2.55,
			MaxPx = 470,
			Alpha = 0.28,
			Extra = true,
			Glow = 8,
			Rim = 2.6,
			Confetti = 24,
			ConfettiMid = 16,
			Confetti2 = 16,
			Coins = 14,
			Float = 0.15,
			Sparkles = 2,
			Beat = 0.27,
			Count = 0.75,
			Hold = 1.6, -- v3: +0.6 с — руки вверх с рыбой над головой видно до карточки
			Scale = 1.1,
			Tension = true,
			Heartbeat = true,
			Title = true,
			Letters = true,
			Flash = WHITE,
			Shake = true,
			Fov = -8,
			Burst = 1.5,
			Trail = 9,
		},
	}

	local CATCH_FALLBACK = FishingConfig.LeapTime + 0.3 -- сигнала приземления нет — открываем сами
	local LANDING_MEMORY = 1.5 -- приземление пришло раньше "Caught" (без прыжка) — помним его, с
	local CATCH_FAILSAFE = 20 -- улов «завис» (ошибка) — через столько секунд всё равно отпускаем
	local STATUS_FADE = 0.2 -- плашка базы и счётчик гаснут / возвращаются, с
	local BUTTON_FADE = 0.3 -- насколько прозрачнее «замёрзшая» кнопка действия
	local WIN_TEXT = "ПОЙМАНА!" -- рыба поймана (про рыбу, а не про игрока)
	--[[
		Кульминация (одной таблицей — бережём регистры, см. «Устройство файла»).
		  WinHeight, WinTime  «ПОЙМАНА!» высотой WinHeight экрана — самое громкое слово мини-игры;
		               живёт WinTime и тает до приземления (перед ударом — миг тишины); в тесной
		               полосе (рыбак, джойстик) — ниже ростом, но не ниже WinLeast px.
		  SkipDwell    после пропуска долей карточка столько секунд не закрывается тапом.
		  Tension      рамка по краям экрана (эпическая и выше): узкая (Size высоты экрана),
		               нарастает From → To к приземлению (Quad In) и обрывается на нём; мифическая —
		               радуга, светлее на Light, бежит по кругу.
		  Shock        удар приземления — тонкое кольцо вокруг рыбы: до Size + Grow × REVEAL.Burst высоты
		               экрана, толщина Thickness px, Time с; без свечения в середине и без вспышки краёв
		               экрана (v3: чёткий удар в точке рыбы, не заливка кадра).
		  Heartbeat    у легендарной и мифической «сердце» бьётся всё чаще (доли LeapTime).
		  TitleDelay, TitleStagger, TitleY, TitleHeight   огромное слово редкости — через TitleDelay
		               после приземления, буквы через TitleStagger, центр на TitleY высоты экрана
		               (v3: в полосе НАД рыбаком и рыбой над головой — FishingLayout.topBand: руки
		               вверх и сама рыба видны; плашки статуса в это время погашены), высота —
		               TitleHeight экрана, но не больше TitleMax px (и не шире просвета между
		               кнопками); лучи за ним бьют из рыбы, середина (RaysHole радиуса) пустая.
		               Сверху — 16 px до панели Roblox; не влезает (огромная рыба на маленьком
		               телефоне) — выше, но правее TopbarRight px (её кнопки меню и чата слева);
		               и там тесно (трофей × HeldScale на телефоне упирается в верх) — сбоку от
		               рыбака с рыбой, где просвет шире, на той же высоте (не мельче TitleSide px;
		               без тач-экрана — не на окне чата: ChatRight, ChatBottom, и не на списке
		               игроков справа вверху: ListLeft, ListBottom — и карточка); v5 (D5): сбоку и
		               тогда, когда над рыбой лишь узкая полоса, а сбоку буквы в TitleBeside раз
		               крупнее (планшет, компьютер: слово над трофеем выходило мелким).
		  TitleRays    лучи сцены слова — тонкие спицы (Width доли диаметра) и на Fade прозрачнее
		               лучей карточки: вокруг рыбы не встаёт жёлтая «заливка» (v3).
		  TitleDim     сцена слова: через At после приземления (кольца удара уже ушли — заливка
		               кадра) экран чуть темнеет целиком (на Add светлее затемнения карточки):
		               лучи и буквы ярче. v3: на телефоне — нет (рыбак с трофеем остаётся ярким).
		  Shine        сложившееся слово один раз пробегает белый блик, с.
		  GrowAt       баннер карточки вырастает из летящего слова на этой доле полёта (CARD.Morph).
		  Lead, Aim    слово трогается к баннеру за Lead до карточки и долетает за Aim (v4: к её
		               рождению оно уже у места баннера — карточка растёт под ним, не «наезжает» на
		               слово посреди экрана; дальше это эффект FxTitleMorph, см. morphTitle).
		  Trophy       трофей над головой «вспыхивает» через столько после «+1» в счётчике.
	]]
	local CLIMAX = {
		WinHeight = 0.17,
		WinLeast = 40,
		WinTime = 0.8,
		SkipDwell = 0.6,
		Tension = { Size = 0.13, From = 0.85, To = 0.5, Light = 0.3 },
		Shock = { Size = 0.36, Grow = 0.18, Thickness = 9, Time = 0.34 },
		TitleRays = { Width = 0.05, Fade = 0.22 },
		Heartbeat = { 0.28, 0.46, 0.62, 0.75, 0.85, 0.93 },
		TitleDelay = 0.05,
		TitleStagger = 0.03,
		TitleY = 0.15,
		TitleHeight = 0.18,
		TitleMax = 110,
		TopbarRight = 172,
		ChatRight = 384, -- без тач-экрана слева вверху окно чата Roblox (до x 368 + 16 px зазора) …
		ChatBottom = 201, -- … и до этой высоты HUD (низ окна — y 184 HUD + 16 px + 1 на округление): ниже
		ListLeft = 324, -- без тач-экрана справа вверху список игроков (Этап 3: с колонками «Деньги» и
		-- «Доход/с» ≈ 8…308 px от края + 16 px; оценка, как tools/preview/gui/backdrop.py) …
		ListBottom = 33, -- … и до этой высоты HUD (низ списка — y 16 HUD + 16 px + 1 на округление)
		TitleSide = 24,
		TitleBeside = 1.25,
		TitleDim = { At = 0.55, Add = 0.2 },
		RaysHole = 0.3,
		Shine = 0.4,
		GrowAt = 0.7,
		Lead = 0.18,
		Aim = 0.22,
		Trophy = 0.15,
	}

	-- Огромное слово редкости (эпическая и выше).
	local TITLE_TEXT: { [string]: string } = {
		Epic = "ЭПИЧЕСКАЯ!",
		Legendary = "ЛЕГЕНДАРНАЯ!",
		Mythic = "МИФИЧЕСКАЯ!",
	}
	-- Ширина буквы (с запасом) в долях высоты строки: широкие, узкие, «!», остальные.
	local WIDE_LETTERS = { ["Ж"] = true, ["Ш"] = true, ["Щ"] = true, ["Ы"] = true, ["Ю"] = true, ["М"] = true }
	local NARROW_LETTERS = { ["Г"] = true, ["Е"] = true, ["З"] = true, ["С"] = true, ["Э"] = true, ["Р"] = true }

	local Layout = require(script.Parent:WaitForChild("FishingLayout")) -- раскладка у своего рыбака
	local CatchFx = require(script.Parent:WaitForChild("CatchFx")) -- вид и движение карточки (UI v5)
	-- Карточка: широкая (телефоны) — на экране ниже WIDE_BELOW пикселей.
	local WIDE_BELOW = 500
	local CARD_ASPECT = 1.55 -- широкая карточка: ширина / высота
	local CARD_TOP_GAP = 4 -- от верха HUD, px (статус под карточкой гаснет)
	local CARD_BOTTOM_CLEAR = 24 -- от низа HUD: 16 px и «живая» обводка (4 px × Rim), px (v3: хотбара нет)
	local CARD_SIDE_GAP = 16 -- до кнопок, джойстика и края экрана, px
	local THUMBSTICK_CLEAR = 111 -- джойстик Roblox на телефоне (до 95 px слева) + зазор, px
	local THUMBSTICK_CLEAR_BIG = 196 -- … на планшете (до 180 px слева)
	--[[
		Карточка (одной таблицей — бережём регистры, см. «Устройство файла»).
		  MaxScale     самая крупная (мифическая) карточка: на телефоне она — во всё свободное место,
		               остальные — во столько раз меньше × свой REVEAL.Scale.
		  Span         баннер шире карточки на 5 % (квадратной — на 8 %), мифическая ещё «дышит»
		               (Breath): столько места по ширине нужно на её ширину.
		  Breath, BreathPeriod   мифическая на месте «дышит» (растёт вверх, низ стоит).
		  Banner       без огромного слова баннер «раскатывается» в c+Banner; Morph — слово летит в
		               баннер c+0 … c+Morph, баннер вырастает из него в его конце (Grow с).
		  Chips        цена — через столько после веса; Count — счёт цены после фишек (шаг долей —
		               REVEAL.Beat: он же — «вдох» цены перед штампом мутации и пауза до подсказки).
		  Linger       сама карточка закрывается не раньше, чем через столько после последней доли.
		  Mash         кнопка действия закрывает показанную карточку, только если с прошлого нажатия
		               прошло столько (её жмут по инерции после «ЛОВИ!»), с.
		  Slide, Rise  имя въезжает справа на долю ширины карточки, фишки поднимаются на долю её высоты.
		  MinHeight    широкая карточка (телефон) не ниже стольких px, если место есть: обычная рыба
		               на маленьком телефоне не «крошечная» (текст на ней не меньше 14 px).
		  DockMin      … а сбоку от рыбака (v3) — не ниже стольких px: на маленьком телефоне
		               лучше чуть меньше, но рядом с ним, чем поверх него.
		  DockShrink, DockCover   запасное место широкой карточки (огромный трофей на маленьком
		               телефоне, UI v5): размеры DockMin × эти доли по очереди — первый, где она
		               закрывает рыбака с трофеем не больше DockCover его прямоугольника (тексты
		               на 0.85 ещё не мельче 12 px).
		  DockSquare, DockSquareMin   квадратная (планшет, компьютер; v5) сбоку от рыбака с трофеем —
		               не меньше такой доли своего размера «посередине» и не меньше стольких px
		               (текст на ней ещё помещается в свои строки); не встала — там, где такая
		               закрывает рыбака с трофеем меньше всего (FishingLayout.leastCover), если это
		               заметно меньше, чем посередине; иначе — посередине, как раньше.
		  DockSquarePhone  маленький телефон, широкой сбоку места нет (огромный трофей): сбоку
		               встаёт квадратная, если она не меньше стольких px.
		  DockSlack    у слова редкости место карточки выбирается дважды (на приземлении — куда
		               лететь слову, и на рождении карточки), рыбак с трофеем за это время чуть
		               сдвигается: оба раза порог «сбоку» ниже на столько px — иначе на впритык
		               помещающемся экране слово летит к середине, а карточка рождается сбоку.
		  PriceText    цена на фишке — до стольких Title (крупное «витринное» число, по своей коробке).
		  PriceFloat   «+$4/с»: через Delay после «приземления» цены (фишка уже пружинит) вылетает из
		               неё за Fly с (Back Out) на свободное место справа от карточки, Lift высоты экрана
		               над ценой (или в 2 и 3.5 раза выше — где просторнее; Gap px от карточки); там
		               тесно — меньше, но не меньше MinTitle × Title; совсем тесно — над строкой
		               веса. Живёт Time с: поднимается (на Rise высоты экрана) и тает. Цену и «×N» не
		               закрывает. У карточки сбоку от рыбака (UI v5) — не на окно с рыбой: над баннером
		               или у её внешнего края (CatchFx.floatSpot; и на пике подъёма не в ряду кнопок
		               меню и чата Roblox — r3, SIMC-C2-03); нет места и там — на верхнюю полоску окна
		               правее наклейки «НОВИНКА!» и живёт Early с (тает с 0.4 с); не влезает и там (узкое
		               окно телефона, SIMC-C2-02) — не вылетает.
		  New          новый вид обычной и редкой рыбы — маленький праздник: Confetti бумажек и
		               Sparks искр из штампа «НОВИНКА!» цветами Colors, лучи не прозрачнее Alpha, не
		               меньше Size (и MaxPx) и с зеленью и золотом, затемнение не светлее Dim, «+$4/с»
		               высотой Float.
		  RefHeight    высота места под карточку на телефоне 844×390: лучи на тач-экране
		               уменьшаются вместе с ним (маленький телефон — меньше заливки).
		  RimRoom      «живая» обводка выступает за карточку: над кнопкой действия — ещё столько, px
		               (UI v5: или толщина её обводки на этом экране × Rim, если та толще —
		               CatchFx.outline; с мутацией обводка карточки толще в 4/3).
		  EdgeRoom     … и ещё столько над кнопкой действия и колонкой: их обводки и значок клавиши
		               тоже выступают за свои прямоугольники (по рисунку — те же 16 px).
		  KeyRoom      … и над кнопкой действия без тач-экрана ещё столько: значок клавиши на её
		               плече «дышит» вместе с «ЗАБРАТЬ!» (квадратная карточка сбоку на компьютере).
		  DesktopRays  без тач-экрана лучи не больше стольких REVEAL.MaxPx (заливка на компьютере).
		  ConfettiMid  мифическая: второй залп конфетти через столько после приземления.
		  Fly          уходя, карточка сама летит снарядом в счётчик (Shrink — её размер у цели, Reach
		               — доля пути, Travel — время, Quad In); через Fly рядом с ней вылетают 🐟 и ★ и
		               долетают вместе с ней за FishTime (★ — одной стайкой, до 6: разлетаются из карточки и
		               летят друг за другом через 2 × StarGap; один покадровый эффект).
		  Fov, FovWide, Yaw, Swing, SwingPeriod, FishBob, FishBobPeriod   рыба во ViewportFrame: камера
		               (на широкой — уже: меньше искажений), рыба вполоборота (нос чуть к камере),
		               покачивается ±Swing (ребром не встаёт) и «дышит» вверх-вниз (доля её высоты).
	]]
	local CARD = {
		MaxScale = 1.1,
		RimRoom = 8,
		EdgeRoom = 10,
		KeyRoom = 3,
		Span = 1.05 * 1.025,
		SquareSpan = 1.08 * 1.025,
		Breath = 1.025,
		BreathPeriod = 1.8,
		Banner = 0.18,
		Morph = 0.32,
		Grow = 0.22,
		Chips = 0.08,
		Count = 0.12,
		Linger = 0.6,
		Mash = 0.3,
		Slide = 0.1,
		Rise = 0.05,
		MinHeight = 165,
		DockMin = 128,
		DockShrink = { 1, 0.95, 0.9, 0.85 },
		DockCover = 0.03,
		DockSquare = 0.6,
		DockSquareMin = 250,
		DockSquarePhone = 166,
		DockSlack = 12,
		PriceText = 1.4,
		PriceFloat = {
			Delay = 0.12,
			Fly = 0.35,
			Time = 0.95,
			Early = 0.8,
			Lift = 0.1,
			Gap = 10,
			MinTitle = 1.2,
			Rise = 0.04,
		},
		New = {
			Confetti = 12,
			Sparks = 16,
			Colors = { Palette.Berry.Top, Palette.Gold.Top, Palette.Leaf.Top, Palette.Sky.Top, WHITE },
			Alpha = 0.4,
			Size = 2.0,
			MaxPx = 480,
			Dim = 0.7,
			Float = 0.11,
		},
		RefHeight = 236,
		DesktopRays = 1.3,
		ConfettiMid = 1.0,
		Fly = 0.05,
		Shrink = 0.12,
		Reach = 0.92,
		Travel = 0.3,
		FishTime = 0.28,
		StarGap = 0.03,
		Fov = 40,
		FovWide = 32,
		Yaw = math.rad(-25),
		Swing = math.rad(30),
		SwingPeriod = 3.2,
		FishBob = 0.03,
		FishBobPeriod = 1.6,
	}

	local CARD_WIDE: { [string]: { [string]: any } } = {
		Banner = { Position = UDim2.fromScale(0.5, 0.025), Size = UDim2.fromScale(1.05, 0.19) },
		-- Витрина: окно рыбы слева, рыба стоит на подиуме (Pedestal). (Дети лица — в долях лица.)
		["Face.Window"] = { Position = UDim2.fromScale(0.03, 0.296), Size = UDim2.fromScale(0.44, 0.676) },
		FishGlow = { Position = UDim2.fromScale(0.25, 0.545), Size = UDim2.fromScale(0.6, 0.6) },
		Pedestal = { Position = UDim2.fromScale(0.25, 0.9), Size = UDim2.fromScale(0.16, 0.115) },
		Viewport = { Position = UDim2.fromScale(0.25, 0.545), Size = UDim2.fromScale(0.42, 0.68) },
		NewStamp = { Position = UDim2.fromScale(0.14, 0.32), Size = UDim2.fromScale(0.26, 0.12) },
		-- (UI v5: чуть выше — обведённый значок мутации у нижнего угла не подходит к джойстику
		-- ближе 16 px на маленьком телефоне.)
		-- (UI v5: «РАДУЖНАЯ!» в одну строку не мельче 12 px и на самой маленькой карточке — шире.)
		MutationLabel = { Position = UDim2.fromScale(0.25, 0.88), Size = UDim2.fromScale(0.46, 0.125), Rotation = -4 },
		NameLabel = { Position = UDim2.fromScale(0.75, 0.272), Size = UDim2.fromScale(0.46, 0.205) },
		-- Цена — главное число карточки: её «фишка» выше веса (крупный текст, уровень Title).
		InfoLabel = { Position = UDim2.fromScale(0.75, 0.485), Size = UDim2.fromScale(0.42, 0.355) },
		["InfoLabel.Weight"] = {
			AnchorPoint = Vector2.new(0, 0),
			Position = UDim2.fromScale(0.08, 0),
			Size = UDim2.fromScale(0.92, 0.38),
		},
		["InfoLabel.Price"] = {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0.08, 1),
			Size = UDim2.fromScale(0.92, 0.54),
		},
		-- «Тапни — забрать!» уровнем Body (≥ 14 px): чуть шире столбика (длинная строка).
		TapHint = { Position = UDim2.fromScale(0.75, 0.96), Size = UDim2.fromScale(0.48, 0.1) },
	}

	-- Карточка, её лучи и заготовка «как в сборщике» (квадратная): возвращаются при смене экрана.
	local cardDefaults: { [Instance]: Place }? = nil
	-- dock — карточка сбоку от своего рыбака (−1 слева, 1 справа; v3, телефон), edge — его край
	-- (px HUD.Fishing) с этой стороны: лучи и затемнение до него не достают.
	-- clip — где видны её лучи (CatchFx.raysClip: по одну сторону от рыбака с трофеем; nil — везде).
	local cardBox: {
		center: Vector2,
		size: Vector2,
		wide: boolean,
		slot: number,
		dock: number?,
		edge: number?,
		clip: Layout.Rect?,
	}? =
		nil

	local catchTrove = Trove.new() -- от "Caught" до карточки: ожидание приземления, слово редкости
	local raysTrove = Trove.new() -- лучи за карточкой (на закрытии сжимаются, потом удаляются)
	local catchSerial = 0 -- номер улова (новый улов отменяет хвосты прошлого)
	local heldSerial = 0 -- чей CounterHold сейчас стоит
	local landingWaiter: ((Vector3?) -> ())? = nil -- ждёт OwnFishLanded
	local lastLanding: { at: number, position: Vector3 }? = nil -- приземление до "Caught"
	cardReveal = REVEAL.Common -- «громкость» открытой карточки
	local cardBeats: { { at: number, run: (instant: boolean) -> (), done: boolean } } = {}
	local skipHooks: { () -> () } = {} -- что ещё довести до конца при пропуске (слово → баннер)
	local stopPriceCount: (() -> ())? = nil
	local faded: { [Instance]: { [string]: number } } = {} -- погашенное (плашки статуса, кнопка)
	local fadeTweens: { [Instance]: Tween } = {} -- … и его идущие твины (возврат их отменяет)
	-- Лучи улова: у слова редкости — с приземления (за словом), иначе — с карточки.
	local cardRays: { serial: number, main: UiFx.Rays, extra: UiFx.Rays?, card: boolean }? = nil

	-- Буква «по ширине» для огромного слова.
	local function letterWidth(ch: string): number
		if ch == "!" then
			return 0.34
		elseif WIDE_LETTERS[ch] then
			return 0.8
		elseif NARROW_LETTERS[ch] then
			return 0.56
		end
		return 0.64
	end

	-- Буквы слова (UTF-8) и их общая ширина в высотах строки.
	local function splitLetters(text: string): ({ string }, number)
		local letters: { string } = {}
		local total = 0
		for _, code in utf8.codes(text) do
			local ch = utf8.char(code)
			table.insert(letters, ch)
			total += letterWidth(ch)
		end
		return letters, total
	end

	-- Погасить элемент со всем содержимым (add = на сколько прозрачнее; 1 — совсем) и запомнить,
	-- как было. Только твины. Временные эффекты (Fx*: кольцо, рябь, «+N», блик — кроме масштаба
	-- FxScale) и всё в них не трогаем и не запоминаем: они уходят сами. Запоминается то, что видно
	-- сейчас, — вид кнопки (applyLook) ставят ДО fadeGroup, а возвращают её мгновенно
	-- (unfadeGroup(…, 0)) и только потом меняют вид: идущий твин иначе перебил бы новый вид.
	local function fadeGroup(root: Instance, add: number, time: number)
		local function isEffect(item: Instance): boolean
			local node: Instance? = item
			while node and node ~= root do
				local name = node.Name
				if string.sub(name, 1, 2) == "Fx" and name ~= "FxScale" then
					return true
				end
				node = node.Parent
			end
			return false
		end
		local items: { Instance } = root:GetDescendants()
		table.insert(items, root)
		for _, item in items do
			if isEffect(item) then
				continue
			end
			local props: { string } = {}
			if item:IsA("GuiObject") then
				table.insert(props, "BackgroundTransparency")
			end
			if item:IsA("TextLabel") or item:IsA("TextButton") then
				table.insert(props, "TextTransparency")
				table.insert(props, "TextStrokeTransparency")
			elseif item:IsA("ImageLabel") or item:IsA("ImageButton") then
				table.insert(props, "ImageTransparency")
			elseif item:IsA("UIStroke") then
				table.insert(props, "Transparency")
			end
			if #props > 0 then
				local saved = faded[item] or {}
				faded[item] = saved
				local goals: { [string]: number } = {}
				for _, prop in props do
					local now = (item :: any)[prop] :: number
					local rest = saved[prop] or now
					saved[prop] = rest
					if rest < 1 then
						goals[prop] = math.min(1, rest + add)
					end
				end
				if next(goals) then
					fadeTweens[item] = UiFx.tween(item, time, goals)
				end
			end
		end
	end

	-- Вернуть погашенное под root как было (и забыть уже удалённое); идущее гашение отменяется.
	local function unfadeGroup(root: Instance, time: number)
		for item, saved in faded do
			local running = fadeTweens[item]
			if running and (item.Parent == nil or item == root or item:IsDescendantOf(root)) then
				running:Cancel()
				fadeTweens[item] = nil
			end
			if item.Parent == nil then
				faded[item] = nil
			elseif item == root or item:IsDescendantOf(root) then
				faded[item] = nil
				if time > 0 then
					UiFx.tween(item, time, saved)
				else
					for prop, rest in saved do
						(item :: any)[prop] = rest
					end
				end
			end
		end
	end

	--------------------------------------------------------------------------------
	-- Улов на экране: CounterHold (прошлое число улова), пока 🐟 не прилетит в «САДОК» — по нему
	-- фишка кнопки (TankButtonController), кошелёк (MoneyController), уведомления, слово у ведра
	--------------------------------------------------------------------------------

	local function holdCounter(serial: number, total: number)
		if total >= 1 then
			heldSerial = serial
			ui.hud:SetAttribute("CounterHold", math.floor(total) - 1)
		end
	end

	-- 🐟 прилетела: кнопка «САДОК» показывает новое число и «встречает» её (в цвете CounterIncoming).
	local function releaseCounter(serial: number)
		if heldSerial == serial then
			heldSerial = 0
			ui.hud:SetAttribute("CounterHold", nil)
			ui.hud:SetAttribute("CounterIncoming", nil)
		end
	end

	--------------------------------------------------------------------------------
	-- Раскладка карточки (квадратная / широкая) и рыба в ней
	--------------------------------------------------------------------------------

	-- UDim2 в пикселях (целые; не число — 0): Offset у UDim — целое.
	function offset(x: number, y: number): UDim2
		local function whole(v: number): number
			return if v == v and math.abs(v) < 1e6 then math.round(v) else 0
		end
		return UDim2.fromOffset(whole(x), whole(y))
	end

	-- Прямоугольник элемента «в покое» (без UIScale и поворота) в пикселях родителя размера
	-- parentSize: Size, Position, AnchorPoint, SizeConstraint и UISizeConstraint.
	local function restRect(gui: GuiObject, place: Place, parentSize: Vector2): (Vector2, Vector2)
		local basis = parentSize
		if place.SizeConstraint == Enum.SizeConstraint.RelativeYY then
			basis = Vector2.new(parentSize.Y, parentSize.Y)
		elseif place.SizeConstraint == Enum.SizeConstraint.RelativeXX then
			basis = Vector2.new(parentSize.X, parentSize.X)
		end
		local size, pos = place.Size, place.Position
		local w = size.X.Scale * basis.X + size.X.Offset
		local h = size.Y.Scale * basis.Y + size.Y.Offset
		local cap = gui:FindFirstChildOfClass("UISizeConstraint")
		if cap and gui ~= ui.card and gui ~= ui.rays then
			w = math.clamp(w, cap.MinSize.X, cap.MaxSize.X)
			h = math.clamp(h, cap.MinSize.Y, cap.MaxSize.Y)
		end
		local x = pos.X.Scale * parentSize.X + pos.X.Offset - place.AnchorPoint.X * w
		local y = pos.Y.Scale * parentSize.Y + pos.Y.Offset - place.AnchorPoint.Y * h
		return Vector2.new(x, y), Vector2.new(w, h)
	end

	local function placeOf(gui: GuiObject): Place
		return {
			Position = gui.Position,
			Size = gui.Size,
			AnchorPoint = gui.AnchorPoint,
			Rotation = gui.Rotation,
			SizeConstraint = gui.SizeConstraint,
		}
	end

	-- Элементы карточки, которые раскладываются заново (путь от карточки → элемент).
	local function cardParts(): { [string]: GuiObject }
		local parts: { [string]: GuiObject } = {}
		for path in CARD_WIDE do
			local node: Instance? = ui.card
			for name in string.gmatch(path, "[^%.]+") do
				node = if node then node:FindFirstChild(name) else nil
			end
			if node and node:IsA("GuiObject") then
				parts[path] = node
			end
		end
		return parts
	end

	-- Заготовка из сборщика (квадратная раскладка): запоминается один раз, до первой перестановки.
	local function rememberDefaults(): { [Instance]: Place }
		local saved = cardDefaults
		if saved then
			return saved
		end
		local fresh: { [Instance]: Place } = {}
		fresh[ui.card] = placeOf(ui.card)
		for _, gui in cardParts() do
			fresh[gui] = placeOf(gui)
		end
		local cap = ui.card:FindFirstChildOfClass("UISizeConstraint")
		if cap then
			-- Предел размера квадратной карточки (её UISizeConstraint ниже отпускается).
			fresh[cap] = {
				Position = UDim2.new(),
				Size = offset(cap.MaxSize.X, cap.MaxSize.Y),
				AnchorPoint = Vector2.zero,
				Rotation = 0,
				SizeConstraint = Enum.SizeConstraint.RelativeXY,
			}
		end
		cardDefaults = fresh
		return fresh
	end

	local function applyPlace(gui: GuiObject, place: Place)
		gui.AnchorPoint = place.AnchorPoint
		gui.SizeConstraint = place.SizeConstraint
		gui.Size = place.Size
		gui.Position = place.Position
		gui.Rotation = place.Rotation
	end

	--[[
		Свободное место по бокам (пиксели HUD.Fishing) для полосы высоты top … bottom: от края экрана
		(или джойстика) до кнопки действия (её подпись-лента выступает на 8 % ширины), кнопки
		прыжка (тач-экран) или колонки кнопок справа («ДОМОЙ»), с зазором CARD_SIDE_GAP. Препятствие, которое целиком ниже (или
		выше) полосы, не мешает: на телефоне джойстик и кнопка действия внизу, под карточкой.
		Так же меряются карточка и огромное слово редкости; shown — у колонки справа мешают только
		показанные кнопки (она растёт снизу вверх, её пустой верх свободен: туда вылетает «+$4/с»);
		reach — кнопка действия и колонка мешают и полосе, которая кончается меньше чем в стольких
		px над ними (UI v5: зазор по рисунку — с обводками).
	]]
	-- Джойстик Roblox (тач-экран; маленький — 95 px слева, верх в 90 px от низа; большой — 180 и
	-- 210) с зазором CARD_SIDE_GAP справа и сверху, px HUD.Fishing; без тач-экрана — nil.
	local function thumbstickBox(rootSize: Vector2): any
		if not UserInputService.TouchEnabled then
			return nil
		end
		local small = math.min(rootSize.X, rootSize.Y) <= WIDE_BELOW
		return Layout.rect(
			0,
			rootSize.Y - (if small then 90 else 210) - CARD_SIDE_GAP,
			if small then THUMBSTICK_CLEAR else THUMBSTICK_CLEAR_BIG,
			rootSize.Y
		)
	end

	local function sideLimits(
		rootSize: Vector2,
		top: number,
		bottom: number,
		shown: boolean?,
		reach: number?
	): (number, number)
		local origin = ui.fishing.AbsolutePosition
		local left, right = CARD_SIDE_GAP, rootSize.X - CARD_SIDE_GAP
		local function block(side: number, x: number, from: number, to: number, near: number?)
			if from < bottom + (near or 0) and to > top then
				if side < 0 then
					left = math.max(left, x + CARD_SIDE_GAP)
				else
					right = math.min(right, x - CARD_SIDE_GAP)
				end
			end
		end
		local stick = thumbstickBox(rootSize)
		if stick then
			block(-1, stick.x1 - CARD_SIDE_GAP, stick.y0 + CARD_SIDE_GAP, rootSize.Y)
			local small = math.min(rootSize.X, rootSize.Y) <= WIDE_BELOW
			-- … и кнопка прыжка справа внизу (её зеркало: маленькая — 95 px от правого края, верх в
			-- 90 px от низа; большая — 170 и 210: на планшете она выше кнопки действия, UI v5).
			block(
				1,
				rootSize.X - (if small then 95 else 170),
				rootSize.Y - (if small then 90 else 210),
				rootSize.Y,
				reach
			)
		end
		local button = ui.actionButton
		if button.Visible then
			local at = button.AbsolutePosition - origin
			-- (Лента подписи шире круга — по её настоящему краю с обводкой; v3: без хотбара
			-- квадратная карточка опускается вровень с лентой.)
			local x = at.X - button.AbsoluteSize.X * 0.08
			local ribbon = button:FindFirstChild("CaptionRibbon")
			local lip = ribbon and ribbon:FindFirstChild("Lip")
			local stroke = lip and lip:FindFirstChildOfClass("UIStroke")
			if ribbon and ribbon:IsA("GuiObject") and ribbon.Visible then
				x = math.min(x, ribbon.AbsolutePosition.X - origin.X - (if stroke then stroke.Thickness else 0))
			end
			block(1, x, at.Y, rootSize.Y, reach)
		end
		local column = ui.hud:FindFirstChild("RightButtons")
		if column and column:IsA("GuiObject") and column.Visible then
			local at = column.AbsolutePosition - origin
			local ribbonOut = 0 -- лента подписи кнопок колонки шире самих кнопок
			local stack = 0 -- … и сколько её снизу занято показанными кнопками (с промежутками)
			local list = column:FindFirstChildOfClass("UIListLayout")
			local gap = if list then list.Padding.Scale * column.AbsoluteSize.Y + list.Padding.Offset else 0
			for _, item in column:GetChildren() do
				local band = item:FindFirstChild("CaptionRibbon")
				if item:IsA("GuiObject") and band and band:IsA("GuiObject") then
					ribbonOut = math.max(ribbonOut, column.AbsoluteSize.X * (band.Size.X.Scale - 1) / 2)
				end
				if item:IsA("GuiObject") and item.Visible then
					stack += item.AbsoluteSize.Y + (if stack > 0 then gap else 0)
				end
			end
			local bottomY = at.Y + column.AbsoluteSize.Y
			block(1, at.X - ribbonOut, if shown then bottomY - stack else at.Y, bottomY, reach)
		end
		return left, right
	end

	--[[
		Место для самой крупной широкой карточки (телефоны, CARD.MaxScale). v3 (UIM-04): СБОКУ от
		своего рыбака с трофеем над головой (FishingLayout.dockSide), там, где шире: слева — над
		джойстиком, справа — над кнопкой действия и левее колонки кнопок; карточка не меньше
		CARD.DockMin. Рыбака не знаем или сбоку тесно (огромная рыба над головой) — как раньше: от
		верха HUD до низа экрана или — если так выйдет крупнее и ближе к середине — над кнопкой
		действия; посередине экрана, если там хватает места, иначе сдвиг от препятствий.
		Возвращает центр, размер и сторону (−1 / 1; nil — не сбоку) с краем рыбака с этой стороны;
		пятое — запасное место (UI v5, D1/D2), если сбоку тесно: в тех же полосах, где карточка
		CARD.DockMin закрывает рыбака с трофеем меньше всего (FishingLayout.leastCover), — когда это
		заметно меньше, чем «посередине» (placeCard берёт его, если не встала и квадратная).
	]]
	local function wideSlot(
		rootSize: Vector2,
		fisher: Layout.Rect?,
		rim: number
	): (Vector2, Vector2, number?, number?, {
		center: Vector2,
		size: Vector2,
		side: number,
		edge: number,
	}?)
		local top = CARD_TOP_GAP
		local floor = rootSize.Y - CARD_BOTTOM_CLEAR
		local mid = rootSize.X / 2
		local button = ui.actionButton
		-- (rim — «живая» обводка карточки, см. placeCard; у кнопки — своя, EdgeRoom)
		local lifted = button.AbsolutePosition.Y - ui.fishing.AbsolutePosition.Y - CARD_SIDE_GAP - rim - CARD.EdgeRoom
		local bands: { Layout.DockBand }? = nil -- (полосы сбоку: для запасного места)
		if fisher then
			local aspect = CARD_ASPECT * CARD.Span
			local small = math.min(rootSize.X, rootSize.Y) <= WIDE_BELOW
			-- слева — над джойстиком (тач-экран), справа — над кнопкой действия
			-- (UI v5: и ещё 1 px — округление рисунка, иначе зазор до джойстика 15.7 px)
			local leftFloor = if UserInputService.TouchEnabled
				then rootSize.Y - (if small then 90 else 210) - CARD_SIDE_GAP - rim - 1
				else floor
			local rightFloor = if button.Visible then math.min(floor, lifted) else floor
			local best: any, bestSide, bestEdge = nil, nil, nil
			-- (Сверху — на CARD_SIDE_GAP ниже: над карточкой у края экрана — кнопки Roblox, у
			-- карточки — «живая» обводка (UI v5: толще — ещё 4 px) и «дыхание».)
			local high = CARD_TOP_GAP + rim + 12
			bands = {}
			for _, side in { -1, 1 } do
				local bottom = if side < 0 then leftFloor else rightFloor
				local left, right = sideLimits(rootSize, high, bottom)
				table.insert(bands, {
					side = side,
					top = high,
					bottom = bottom,
					left = left + (rim + CARD.RimRoom) / 2,
					right = right - (rim + CARD.RimRoom) / 2,
				})
				local slot = Layout.dockSide(
					side,
					fisher,
					Vector2.new(rootSize.X, bottom - high),
					CARD.DockMin * aspect,
					high,
					bottom,
					aspect,
					-- (UI v5: толстая «живая» обводка баннера и «дыхание» выступают за «отпечаток» — ещё
					-- полсуммы rim и RimRoom)
					if side < 0 then left + (rim + CARD.RimRoom) / 2 else right - (rim + CARD.RimRoom) / 2
				)
				-- (Слева — чуть охотнее: рыбак с трофеем между карточкой и «ЗАБРАТЬ!».)
				local area = if slot
					then (slot.x1 - slot.x0) * (slot.y1 - slot.y0) * (if side < 0 then 1.1 else 1)
					else 0
				if slot and (not best or area > best.area) then
					best = { rect = slot, area = area }
					bestSide, bestEdge = side, if side < 0 then fisher.x0 else fisher.x1
				end
			end
			if best then
				local rect = best.rect
				local w = (rect.x1 - rect.x0) / CARD.Span
				return Vector2.new((rect.x0 + rect.x1) / 2, (rect.y0 + rect.y1) / 2),
					Vector2.new(w, w / CARD_ASPECT),
					bestSide,
					bestEdge,
					nil
			end
		end
		local bottoms = { floor }
		if button.Visible and lifted < floor and lifted > top + 80 then
			table.insert(bottoms, lifted)
		end
		local best, bestCenter, bestSize = -math.huge, Vector2.new(mid, (top + floor) / 2), Vector2.new(120, 80)
		for _, bottom in bottoms do
			local left, right = sideLimits(rootSize, top, bottom)
			local h = math.max(bottom - top, 60)
			local w = math.min(h * CARD_ASPECT, math.max(right - left, 120) / CARD.Span)
			h = math.min(h, w / CARD_ASPECT)
			local half = w * CARD.Span / 2
			local cx = math.clamp(mid, left + half, math.max(left + half, right - half))
			-- Крупнее — лучше, но сдвиг от середины экрана дорог (карточка «съехала» — выглядит сломанной).
			local score = w * h * (1 - 2 * math.abs(cx - mid) / math.max(rootSize.X, 1))
			if score > best then
				best = score
				bestCenter = Vector2.new(cx, bottom - h / 2)
				bestSize = Vector2.new(w, h)
			end
		end
		if fisher and bands then
			-- Запасное место: там, где карточка CARD.DockMin закрывает рыбака с трофеем меньше всего
			-- (огромный мифический трофей на маленьком телефоне) — если заметно меньше, чем здесь;
			-- UI v5 (SIMC-C1-02): чуть меньше (CARD.DockShrink), если так она встаёт рядом с рыбой.
			local rect, side, cover = Layout.leastCoverScaled(
				fisher,
				bands,
				CARD.DockMin * CARD_ASPECT,
				CARD.DockMin,
				CARD.Span,
				CARD.DockShrink,
				CARD.DockCover * (fisher.x1 - fisher.x0) * (fisher.y1 - fisher.y0)
			)
			local foot = bestSize * Vector2.new(CARD.Span, 1) / 2
			local here = Layout.overlapArea(
				Layout.rect(bestCenter.X - foot.X, bestCenter.Y - foot.Y, bestCenter.X + foot.X, bestCenter.Y + foot.Y),
				fisher
			)
			if rect and side and cover and cover < here * 0.7 then
				return bestCenter,
					bestSize,
					nil,
					nil,
					{
						center = Vector2.new((rect.x0 + rect.x1) / 2, (rect.y0 + rect.y1) / 2),
						size = Vector2.new(rect.x1 - rect.x0, rect.y1 - rect.y0),
						side = side,
						edge = if side < 0 then rect.x1 else rect.x0,
					}
			end
		end
		return bestCenter, bestSize, nil, nil, nil
	end

	-- Затемнение — четыре полосы ВОКРУГ карточки (заходят под её скруглённые края на r px и далеко
	-- за края экрана): середину закрывает сама карточка, второй раз её не затемняем (заливка). У
	-- широкой карточки (телефон) — только верх и низ, как кадр в кино: по бокам от неё узкие
	-- полоски мира, а лучи видны над и под ней. Без карточки (center = nil, сцена огромного слова)
	-- — верхняя полоса на весь экран, остальные пустые.
	-- v3 (UIM-04): карточка сбоку от рыбака (dock −1 / 1, edge — его край) — одна полоса на её
	-- стороне экрана, которая к рыбаку тает (UIGradient "Fade"): рыбак с трофеем остаётся ярким.
	local function placeDim(center: Vector2?, size: Vector2?, wide: boolean?, dock: number?, edge: number?)
		local topBand, bottomBand, leftBand, rightBand = table.unpack(ui.dimBands)
		for _, band in { leftBand, rightBand } do
			local fade = band:FindFirstChild("Fade")
			if fade and fade:IsA("UIGradient") then
				fade.Enabled = false
			end
		end
		if not center or not size then
			topBand.Position = UDim2.fromScale(-1, -1)
			topBand.Size = UDim2.fromScale(3, 3)
			for _, band in { bottomBand, leftBand, rightBand } do
				band.Size = UDim2.new()
			end
			return
		end
		if dock and edge then
			local width = ui.fishing.AbsoluteSize.X
			local band = if dock < 0 then leftBand else rightBand
			for _, other in { topBand, bottomBand, if dock < 0 then rightBand else leftBand } do
				other.Size = UDim2.new()
			end
			band.Visible = true
			-- Полоса от края экрана (и за ним — вырезы) до самого рыбака (edge — с запасом
			-- Layout.FISHER_PAD); плавно тает от середины карточки: над и под карточкой у рыбака —
			-- светлее, у края экрана — темнее, сам рыбак не затемнён.
			local stop = edge - dock * Layout.FISHER_PAD
			local from = center.X
			local span = (if dock < 0 then stop else width - stop) + width
			band.Position = if dock < 0 then UDim2.new(-1, 0, -1, 0) else UDim2.new(0, math.round(stop), -1, 0)
			band.Size = UDim2.new(1, math.round(if dock < 0 then stop else width - stop), 3, 0)
			local fade = band:FindFirstChild("Fade")
			if fade and fade:IsA("UIGradient") then
				local k = math.clamp(if dock < 0 then (width + from) / span else (from - stop) / span, 0.01, 0.99)
				fade.Enabled = true
				fade.Rotation = 0
				fade.Transparency = if dock < 0
					then NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0),
						NumberSequenceKeypoint.new(k, 0),
						NumberSequenceKeypoint.new(1, 1),
					})
					else NumberSequence.new({
						NumberSequenceKeypoint.new(0, 1),
						NumberSequenceKeypoint.new(k, 0),
						NumberSequenceKeypoint.new(1, 0),
					})
			end
			return
		end
		local r = math.min(size.Y * 0.1, 22)
		local left, right = center.X - size.X / 2 + r, center.X + size.X / 2 - r
		local top, bottom = center.Y - size.Y / 2 + r, center.Y + size.Y / 2 - r
		local function whole(v: number): number
			return math.round(v)
		end
		topBand.Position = UDim2.new(-1, 0, -1, 0)
		topBand.Size = UDim2.new(3, 0, 1, whole(top))
		bottomBand.Position = UDim2.new(-1, 0, 0, whole(bottom))
		bottomBand.Size = UDim2.new(3, 0, 2, -whole(bottom))
		leftBand.Position = UDim2.new(-1, 0, 0, whole(top))
		leftBand.Size = UDim2.new(1, whole(left), 0, whole(bottom - top))
		rightBand.Position = UDim2.new(0, whole(right), 0, whole(top))
		rightBand.Size = UDim2.new(2, -whole(right), 0, whole(bottom - top))
		leftBand.Visible = not wide
		rightBand.Visible = not wide
	end

	-- Затемнение: прозрачность полос → target за time (после delay).
	local function dimTo(target: number, time: number, delay: number?)
		for _, band in ui.dimBands do
			UiFx.tween(
				band,
				time,
				{ BackgroundTransparency = target },
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out,
				delay
			)
		end
	end

	-- Поставить карточку (и её лучи) на место: центр и размер в пикселях; внутри — широкая или
	-- квадратная раскладка. scale — меньше для обычной рыбы. trophy — где на экране (будет) рыба
	-- над головой (fishBox: сервер ставит её чуть позже): карточка не встаёт на неё.
	function placeCard(scale: number, trophy: Layout.Rect?, slack: number?, look: Reveal?)
		--[[
			Квадратная карточка (планшет, компьютер) СБОКУ от рыбака с трофеем (UI v5, D1: посередине
			она закрывала больше половины рыбы над головой): полосы слева и справа от него — во всю
			высоту и над препятствиями (джойстик, кнопка действия, показанные кнопки колонки; без
			тач-экрана слева вверху — окно чата), FishingLayout.cardDock выбирает, где карточка
			крупнее; не меньше CARD.DockSquare её размера «посередине» (и не меньше DockSquareMin px —
			иначе текст не помещается в свои строки). keepout — рыбак с трофеем (с запасом); want —
			размер «посередине»; aspect — её ширина / высота; least — не меньше стольких px (по
			умолчанию — см. выше), минус slack (CARD.DockSlack). nil — сбоку не помещается.
			look.Rim — во сколько раз толще обводка карточки («живая», reveal.Rim): зазоры до кнопок
			и края — по ней.
		]]
		-- (UI v5: «живая» обводка толще RimRoom на крупном экране; с мутацией — в 4/3)
		local rim = math.max(CARD.RimRoom, CatchFx.outline(ui.card, math.max(look and look.Rim or 1, 4 / 3)))
		if look and (UIConfig.Rarity[look.Id] or UIConfig.Rarity.Common).Rainbow then
			-- (мифическая потом «дышит» — CARD.Breath: шире и выше на столько px; карточка — до
			-- 0.6 высоты экрана, не выше 420 px)
			rim += math.ceil((CARD.Breath - 1) * math.min(ui.fishing.AbsoluteSize.Y * 0.6, 420))
		end
		local function squareDock(
			rootSize: Vector2,
			keepout: Layout.Rect,
			want: number,
			aspect: number,
			least: number?
		): any
			local origin = ui.fishing.AbsolutePosition
			local touch = UserInputService.TouchEnabled
			-- (обводка карточки по рисунку, rim; до кнопок — ещё их обводки, EdgeRoom; над кнопкой
			-- действия без тач-экрана — ещё KeyRoom: значок клавиши на её плече «дышит» вместе с
			-- «ЗАБРАТЬ!», SIMC-C2-04)
			local reach = CARD_SIDE_GAP + rim + CARD.EdgeRoom
			local high = CARD_TOP_GAP + rim + 12
			local floor = rootSize.Y - CARD_BOTTOM_CLEAR
			local floors = { floor }
			local button = ui.actionButton
			if button.Visible then
				table.insert(floors, button.AbsolutePosition.Y - origin.Y - reach - (if touch then 0 else CARD.KeyRoom))
			end
			if touch then
				-- над джойстиком (большой — 210 px от низа; ещё 1 px — округление рисунка)
				local small = math.min(rootSize.X, rootSize.Y) <= WIDE_BELOW
				table.insert(floors, rootSize.Y - (if small then 90 else 210) - CARD_SIDE_GAP - rim - 1)
			end
			local column = ui.hud:FindFirstChild("RightButtons")
			if column and column:IsA("GuiObject") and column.Visible then
				-- над показанными кнопками колонки (она растёт снизу вверх; как в sideLimits)
				local list = column:FindFirstChildOfClass("UIListLayout")
				local gap = if list then list.Padding.Scale * column.AbsoluteSize.Y + list.Padding.Offset else 0
				local stack = 0
				for _, item in column:GetChildren() do
					if item:IsA("GuiObject") and item.Visible then
						stack += item.AbsoluteSize.Y + (if stack > 0 then gap else 0)
					end
				end
				if stack > 0 then
					local bottomY = column.AbsolutePosition.Y - origin.Y + column.AbsoluteSize.Y
					table.insert(floors, bottomY - stack - reach)
				end
			end
			local bands: { Layout.DockBand } = {}
			for _, side in { -1, 1 } do
				for _, bottom in floors do
					local tops = { high }
					if not touch then
						-- (без тач-экрана: окно чата слева вверху и список игроков справа вверху —
						-- ниже них, с обводкой карточки rim)
						table.insert(tops, (if side < 0 then CLIMAX.ChatBottom else CLIMAX.ListBottom) + rim)
					end
					for _, top in tops do
						if bottom - top > 0 then
							local left, right = sideLimits(rootSize, top, bottom, true, reach)
							if not touch and top < CLIMAX.ChatBottom + rim then
								left = math.max(left, CLIMAX.ChatRight + rim)
							end
							if not touch and top < CLIMAX.ListBottom + rim then
								right = math.min(right, rootSize.X - CLIMAX.ListLeft - rim)
							end
							-- (полсуммы rim и RimRoom: «живая» обводка баннера и «дыхание» выступают)
							table.insert(bands, {
								side = side,
								top = top,
								bottom = bottom,
								left = left + (rim + CARD.RimRoom) / 2,
								right = right - (rim + CARD.RimRoom) / 2,
							})
						end
					end
				end
			end
			local smallest = (least or math.max(want * CARD.DockSquare, CARD.DockSquareMin)) - (slack or 0)
			local rect, side, edge =
				Layout.cardDock(keepout, bands, want, math.min(smallest, want), aspect, CARD.SquareSpan)
			-- (не встала — полосы и размер для запасного места, см. ниже)
			return { rect = rect, side = side, edge = edge, bands = bands, least = math.min(smallest, want) }
		end
		local defaults = rememberDefaults()
		local root = ui.fishing
		local rootSize = root.AbsoluteSize
		local wide = rootSize.Y < WIDE_BELOW
		local center: Vector2, size: Vector2
		local dock: number?, edge: number? = nil, nil
		local fixed = false -- (место уже под свой размер: сбоку от рыбака)
		local fisher = fisherRect()
		if fisher and trophy then
			local pad = Layout.FISHER_PAD
			fisher = Layout.rect(
				math.min(fisher.x0, trophy.x0 - pad),
				math.min(fisher.y0, trophy.y0 - pad),
				math.max(fisher.x1, trophy.x1 + pad),
				fisher.y1
			)
		end
		local spare = nil -- (запасное место широкой карточки, см. wideSlot)
		if wide then
			center, size, dock, edge, spare = wideSlot(rootSize, fisher, rim)
		end
		-- (v5: на маленьком телефоне огромный трофей не оставляет места широкой карточке сбоку —
		-- тогда сбоку встаёт квадратная, она уже: не меньше CARD.DockSquarePhone px; не встала и
		-- она — широкая CARD.DockMin там, где меньше всего закрывает трофей (запасное место
		-- wideSlot), а нет и его — как раньше.)
		if not wide or (fisher and not dock) then
			local pos, box = restRect(ui.card, defaults[ui.card], rootSize)
			local capPlace = nil
			local cap = ui.card:FindFirstChildOfClass("UISizeConstraint")
			if cap then
				capPlace = defaults[cap]
			end
			if capPlace then
				local limit = capPlace.Size
				local w = math.min(box.X, limit.X.Offset)
				local h = math.min(box.Y, limit.Y.Offset)
				pos = Vector2.new(
					pos.X + (box.X - w) * defaults[ui.card].AnchorPoint.X,
					pos.Y + (box.Y - h) * defaults[ui.card].AnchorPoint.Y
				)
				box = Vector2.new(w, h)
			end
			-- v5 (D1): сбоку от рыбака с трофеем, если там помещается (обводка «живой» рамки — ещё
			-- CARD.RimRoom px от него).
			local docked = if fisher
				then squareDock(rootSize, {
					x0 = fisher.x0 - CARD.RimRoom,
					y0 = fisher.y0,
					x1 = fisher.x1 + CARD.RimRoom,
					y1 = fisher.y1,
				}, box.X * scale, box.X / math.max(box.Y, 1), if wide then CARD.DockSquarePhone else nil)
				else nil
			if docked and docked.rect then
				local rect = docked.rect
				center = Vector2.new((rect.x0 + rect.x1) / 2, (rect.y0 + rect.y1) / 2)
				size = Vector2.new(rect.x1 - rect.x0, rect.y1 - rect.y0)
				dock, edge, fixed = docked.side, docked.edge - docked.side * CARD.RimRoom, true
				wide = false
			elseif not wide then
				center, size = pos + box / 2, box
				-- (v5: и сбоку не встала — там, где карточка не меньше least закрывает рыбака с
				-- трофеем меньше всего, если заметно меньше, чем посередине)
				local rect, side, cover = nil, nil, nil
				if docked and fisher then
					rect, side, cover = Layout.leastCover(
						fisher,
						docked.bands,
						docked.least,
						docked.least * box.Y / math.max(box.X, 1),
						CARD.SquareSpan
					)
				end
				if
					rect
					and side
					and fisher
					and (cover or 0)
						< 0.7 * Layout.overlapArea(Layout.rect(pos.X, pos.Y, pos.X + box.X, pos.Y + box.Y), fisher)
				then
					center = Vector2.new((rect.x0 + rect.x1) / 2, (rect.y0 + rect.y1) / 2)
					size = Vector2.new(rect.x1 - rect.x0, rect.y1 - rect.y0)
					dock, edge, fixed = side, if side < 0 then rect.x1 else rect.x0, true
				end
			elseif spare then
				-- (v5: и квадратная не встала — там, где широкая меньше всего закрывает трофей)
				center, size, dock, edge, fixed = spare.center, spare.size, spare.side, spare.edge, true
			end
		end
		-- Размер по редкости, низ остаётся на месте (над хотбаром). Широкая карточка: место — под
		-- самую крупную (мифическую), остальные — меньше, но не ниже CARD.MinHeight (маленький
		-- телефон: обычная рыба не «крошечная»). slot — высота этого места (лучи).
		local slot = size.Y
		local grow = if fixed
			then 1
			elseif wide then math.max(scale / CARD.MaxScale, math.min(1, CARD.MinHeight / math.max(slot, 1)))
			else scale
		local scaled = size * grow
		-- (Сбоку от рыбака — по середине своего места; иначе низ остаётся на месте.)
		center += Vector2.new(0, if dock then 0 else (size.Y - scaled.Y) / 2)
		size = scaled
		if not wide and not fixed then
			-- Квадратная не налезает на кнопку действия, джойстик (планшет 4:3) и колонку справа:
			-- сдвиг, а не хватает места — меньше (баннер шире на 8 %, мифическая ещё «дышит»); и не
			-- выше верха HUD (крупная мифическая на невысоком экране).
			local bottom = math.min(center.Y + size.Y / 2, rootSize.Y - CARD_BOTTOM_CLEAR)
			local left, right = sideLimits(rootSize, bottom - size.Y, bottom)
			local fit = math.min(1, (right - left) / (size.X * CARD.SquareSpan), (bottom - CARD_TOP_GAP) / size.Y)
			size *= fit
			local half = size.X * CARD.SquareSpan / 2
			center =
				Vector2.new(math.clamp(center.X, left + half, math.max(left + half, right - half)), bottom - size.Y / 2)
		end
		-- (UI v5: слой лучей CatchRays ставит startRays — CatchFx.raysFrame.)
		local cap = ui.card:FindFirstChildOfClass("UISizeConstraint")
		if cap then
			cap.MaxSize = Vector2.new(4096, 4096)
		end
		applyPlace(ui.card, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			SizeConstraint = Enum.SizeConstraint.RelativeXY,
			Size = offset(size.X, size.Y),
			Position = offset(center.X, center.Y),
			Rotation = 0,
		})
		for path, gui in cardParts() do
			local base = defaults[gui]
			local place = base
			local wideSpec = if wide then CARD_WIDE[path] else nil
			if wideSpec then
				place = {
					Position = wideSpec.Position or base.Position,
					Size = wideSpec.Size or base.Size,
					AnchorPoint = wideSpec.AnchorPoint or base.AnchorPoint,
					Rotation = wideSpec.Rotation or base.Rotation,
					SizeConstraint = base.SizeConstraint,
				}
			end
			applyPlace(gui, place)
		end
		CatchFx.stampMin(ui.newStamp, size.X) -- (UI v5: на узкой карточке наклейка уже)
		-- Этап 3: наклейка садка на правом нижнем углу, подсказка «закрыть» левее (CatchFx.tankRow).
		CatchFx.tankRow(
			ui.tankStamp,
			ui.tapHint,
			cardTank,
			size,
			UserInputService.TouchEnabled,
			if wide then size.X else nil
		)
		cardBox = {
			center = center,
			size = size,
			wide = wide,
			slot = slot,
			dock = dock,
			edge = edge,
			clip = if dock and fisher then CatchFx.raysClip(fisher, center, size, rootSize) else nil,
		}
		placeDim(center, size, wide, dock, edge)
		local rays = cardRays
		if rays and rays.card then
			-- (экран поменял размер: лучи — за карточкой на новом месте, обрезка — по нему)
			CatchFx.raysFrame(ui.rays, rootSize, cardBox and cardBox.clip)
			for _, ring in { rays.main, rays.extra } do
				if ring then
					CatchFx.aimRays(ring.holder, ui.rays, center, ring.holder.Size.X.Offset)
				end
			end
		end
	end

	-- Прямоугольник элемента карточки «в покое» (пиксели HUD.Fishing) — куда влетает слово
	-- редкости и откуда вылетает 🐟 (карточка в этот миг может ещё расти или уже сжиматься).
	local function cardRect(gui: GuiObject): (Vector2, Vector2)
		local box = cardBox
		if not box then
			return gui.AbsolutePosition - ui.fishing.AbsolutePosition, gui.AbsoluteSize
		end
		local origin = box.center - box.size / 2
		local parentPos, parentSize = origin, box.size
		local chain: { GuiObject } = {}
		local node: Instance? = gui
		while node and node ~= ui.card do
			if node:IsA("GuiObject") then
				table.insert(chain, 1, node)
			end
			node = node.Parent
		end
		for _, item in chain do
			local pos, size = restRect(item, placeOf(item), parentSize)
			parentPos, parentSize = parentPos + pos, size
		end
		return parentPos, parentSize
	end

	-- Модель рыбы: Assets.Fish.<Id>.<мутация или Normal>.
	local function fishTemplate(fish: FishingRules.FishData): Model?
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local fishFolder = assets and assets:FindFirstChild("Fish")
		local variants = fishFolder and fishFolder:FindFirstChild(fish.Id)
		if not variants then
			return nil
		end
		local model = variants:FindFirstChild(fish.Mutation or "Normal") or variants:FindFirstChild("Normal")
		return if model and model:IsA("Model") then model else nil
	end

	-- Где встанет рыба над головой своего рыбака на экране (px HUD.Fishing), ещё до того, как её
	-- поставил сервер: от макушки + FishingConfig.HeldFishGap вверх на высоту модели рыбы и вширь
	-- на её длину (× HeldScale редкости, с запасом на вес). nil — не видно.
	local function fishBox(fish: FishingRules.FishData): Layout.Rect?
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		local camera = Workspace.CurrentCamera
		if not head or not head:IsA("BasePart") or not camera then
			return nil
		end
		local template = fishTemplate(fish)
		local height, length = 1.5, 3
		if template then
			local _, size = template:GetBoundingBox()
			height = math.max(size.Y, math.min(size.X, size.Z) * 0.5)
			length = math.max(size.X, size.Z)
		end
		local scale = (FishingConfig.HeldScale[fish.Rarity] or 1) * 1.15
		local base = head.Position + Vector3.new(0, head.Size.Y / 2 + FishingConfig.HeldFishGap, 0)
		local half = camera.CFrame.RightVector * (length * scale / 2)
		local top = camera:WorldToScreenPoint(base + Vector3.new(0, height * scale, 0))
		local a = camera:WorldToScreenPoint(base - half)
		local b = camera:WorldToScreenPoint(base + half)
		if top.Z <= 0 or a.Z <= 0 or b.Z <= 0 then
			return nil
		end
		local origin = ui.fishing.AbsolutePosition
		return Layout.rect(
			math.min(a.X, b.X) - origin.X,
			top.Y - origin.Y,
			math.max(a.X, b.X) - origin.X,
			math.max(a.Y, b.Y) - origin.Y
		)
	end

	--[[
		Рыба во ViewportFrame: центр габаритов в нуле, вполоборота, покачивается ±30° и чуть «дышит»
		(ребром к камере не встаёт). Камера вписывает рыбу по обеим осям окна (FUI-02): по высоте —
		её высоту, по ширине — диагональ (X, Z), какой бы стороной она ни повернулась.
	]]
	local function showFishModel(fish: FishingRules.FishData)
		local template = fishTemplate(fish)
		if not template then
			return
		end
		local model = cardTrove:Add(template:Clone())
		local box, size = model:GetBoundingBox()
		local centred = model:GetPivot() - box.Position
		model:PivotTo(CFrame.Angles(0, CARD.Yaw, 0) * centred)
		model.Parent = ui.viewport

		local fov = if cardBox and cardBox.wide then CARD.FovWide else CARD.Fov
		local _, view = cardRect(ui.viewport)
		local vTan = math.tan(math.rad(fov / 2))
		local hTan = vTan * view.X / math.max(view.Y, 1)
		local halfLen = Vector2.new(size.X, size.Z).Magnitude / 2
		local halfH = size.Y / 2
		local distance = math.max(halfH * 1.18 / vTan, halfLen * 1.08 / hTan, 0.5)
		local camera = cardTrove:Add(Instance.new("Camera"))
		camera.FieldOfView = fov
		camera.CFrame = CFrame.lookAt(Vector3.new(0, halfH * 0.35, distance), Vector3.zero)
		camera.Parent = ui.viewport
		ui.viewport.CurrentCamera = camera

		local elapsed = 0
		cardTrove:Add(UiFx.schedule(function(dt: number): boolean
			if model.Parent == nil then
				return false
			end
			elapsed += dt
			local yaw = CARD.Yaw + CARD.Swing * math.sin(elapsed * 2 * math.pi / CARD.SwingPeriod)
			local bob = size.Y * CARD.FishBob * math.sin(elapsed * 2 * math.pi / CARD.FishBobPeriod)
			model:PivotTo(CFrame.new(0, bob, 0) * CFrame.Angles(0, yaw, 0) * centred)
			return true
		end))
	end

	local function fillCard(fish: FishingRules.FishData, style: UIConfig.RarityStyle)
		local rarity = FishingRules.GetRarity(fish.Rarity)

		-- Лицо карточки кремовое; у легендарной и мифической — чуть в цвет редкости (у мифической
		-- по нему ещё бежит пастельная радуга — её запускает openCard).
		local cream = Palette.Cream
		UiFx.setCandy(
			ui.card,
			if style.Flash
				then { Top = cream.Top, Bottom = cream.Bottom:Lerp(style.Top, 0.15), Lip = cream.Lip }
				else cream
		)

		-- Баннер редкости и подиум рыбы — в её цветах (мифическая — радуга, бегущая по баннеру: её
		-- запускает openCard; у подиума светлый верх с тенью рыбы — CatchFx.paintPodium).
		UiFx.setCandy(ui.banner, swatchOf(style))
		CatchFx.paintPodium(ui.pedestal, style)
		if style.Rainbow then
			ui.bannerFill.Color = UiFx.sequence(UIConfig.Rainbow)
			ui.bannerFill.Rotation = 0
		else
			ui.bannerFill.Rotation = 90
		end
		ui.rarityLabel.Text = upper(if rarity then rarity.Name else fish.Rarity)
		-- За рыбой — маленькие лучи (openCard); диск-подложка не нужен (лишняя заливка).
		local disc = ui.fishGlow:FindFirstChild("Disc")
		if disc and disc:IsA("GuiObject") then
			disc.BackgroundColor3 = style.Top
			disc.Visible = false
		end
		ui.nameLabel.Text = FishingRules.DisplayName(fish)
		ui.nameFill.Color, ui.nameFill.Rotation = CatchFx.nameColors(fish.Rarity, style)

		-- Штамп мутации на углу рыбы: «ЗОЛОТАЯ ×2!»; Text — значение «Золотая мутация ×2».
		local mutationText = FishingRules.MutationLabel(fish)
		local mutation = if fish.Mutation then FishingRules.GetMutation(fish.Mutation) else nil
		local mutationStyle = if fish.Mutation then UIConfig.Mutations[fish.Mutation] else nil
		ui.mutationLabel.Visible = mutationText ~= nil
		ui.mutationLabel.Text = mutationText or ""
		local wideBox = if cardBox and cardBox.wide then cardBox.size.X else nil
		-- (строка штампа, px: по ширине карточки и долям штампа и его подписи)
		local stampRoom = if cardBox
			then cardBox.size.X * ui.mutationLabel.Size.X.Scale * ui.mutationCaption.Size.X.Scale
			else nil
		ui.mutationCaption.Text = if mutation
			then CatchFx.stampText(
				mutation.Name,
				mutation.Multiplier,
				wideBox ~= nil,
				cardBox and cardBox.size.X,
				stampRoom
			)
			else ""
		ui.tankStamp.Visible = false -- (его доля — после цены; подсказку и штамп ставит placeCard)
		ui.priceMult.Text = if mutation then `×{mutation.Multiplier}` else ""
		ui.priceMult.Visible = false
		if mutationStyle then
			UiFx.setCandy(ui.mutationLabel, swatchOf(mutationStyle))
			ui.mutationIcon.Text = mutationStyle.Icon
			if mutationStyle.Effect == "rainbow" then
				ui.mutationFill.Color = UiFx.sequence(UIConfig.Rainbow)
				ui.mutationFill.Rotation = 0
			else
				ui.mutationFill.Rotation = 90
			end
		end

		local kg = FishingRules.FormatKg(fish.Kg)
		local value = math.round(fish.Value)
		ui.infoLabel.Text = CatchFx.infoText(kg, value)
		ui.weightLabel.Text = upper(kg) -- «2,1 КГ»: фишки — заглавными
		ui.priceLabel.Text = CatchFx.money(0)
		-- Цена — главное число карточки: «витринное», по своей коробке (≈ 0.8 лица фишки) — до
		-- CARD.PriceText × Title, не меньше Button − 2 (не уровень шкалы: fitText её не трогает).
		ui.priceLabel:SetAttribute("TextTier", nil)
		local fit = ui.priceLabel:FindFirstChildOfClass("UITextSizeConstraint")
		if fit then
			fit.MinTextSize = 1 -- (Min не бывает больше Max и в промежутке)
			fit.MaxTextSize = math.round(UiFx.textSize("Title") * CARD.PriceText)
			fit.MinTextSize = math.max(12, UiFx.textSize("Button") - 2)
		end
	end

	--------------------------------------------------------------------------------
	-- Мутация: рамка карточки, эффекты штампа
	--------------------------------------------------------------------------------

	-- Эффект штампа мутации по её стилю: золото — звёздочки, неон — светится, радуга — бежит.
	-- (Звёздочки — по бокам штампа, не на его буквах: outside, ART-02.)
	local function mutationFx(style: UIConfig.MutationStyle)
		local badge = ui.mutationLabel
		if style.Effect == "sparkles" then
			cardTrove:Add(UiFx.sparkles(badge, { rate = 3, size = 0.8, area = 0.12, outside = true }))
		elseif style.Effect == "pulse" then
			cardTrove:Add(UiFx.glowRing(badge, {
				loop = true,
				color = style.Top,
				scale = 1.2,
				thickness = 3,
				time = 0.8,
				interval = 0.7,
			}))
		elseif style.Effect == "rainbow" then
			cardTrove:Add(UiFx.rainbow(ui.mutationFill, { speed = 0.6 }))
			cardTrove:Add(
				UiFx.sparkles(badge, { rate = 2, size = 0.8, area = 0.12, icons = { "✨", "🌈" }, outside = true })
			)
		end
	end

	--[[
		«Живая» обводка (UIStroke уже есть — лишней заливки нет): белая под градиентом colors
		(Rotation 45) и толще в thick раз; effect — "pulse": прозрачность 0 ↔ depth за period,
		"sweep": по ней пробегает светлая полоса (period на проход), "spin": градиент вращается
		(оборот за period). Только твины; с уборкой cardTrove всё как было. Толщина «как было» —
		из сборщика (BaseThickness под этот экран, UiFx.strokeThickness), а не текущая: чужой
		недоигравший твин не сделает обводку толстой навсегда.
		  Редкость (эпическая и выше): эпическая — виноградная дышит, легендарная — по золоту бежит
		  блик, мифическая — вращается радуга; с мутацией — на обводке баннера (обводка карточки —
		  мутации). Мутация: золото переливается, неон пульсирует, радуга вращается (толще в 4/3).
	]]
	local function rim(
		stroke: UIStroke,
		colors: { Color3 },
		effect: string,
		thick: number,
		period: number,
		depth: number?
	)
		local color, thickness, transparency = stroke.Color, UiFx.strokeThickness(stroke), stroke.Transparency
		local fill = Instance.new("UIGradient")
		fill.Name = "FxRimFill"
		fill.Rotation = 45
		fill.Color = UiFx.sequence(colors)
		fill.Parent = stroke
		stroke.Color = WHITE
		stroke.Thickness = thickness * thick
		local loop: Tween
		if effect == "spin" then
			loop = TweenService:Create(
				fill,
				TweenInfo.new(period, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1),
				{ Rotation = 405 }
			)
		elseif effect == "sweep" then
			fill.Offset = Vector2.new(-1, 0)
			loop = TweenService:Create(
				fill,
				TweenInfo.new(period, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1),
				{ Offset = Vector2.new(1, 0) }
			)
		else
			loop = TweenService:Create(
				stroke,
				TweenInfo.new(period / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Transparency = depth or 0.45 }
			)
		end
		loop:Play()
		cardTrove:Add(function()
			loop:Cancel()
			fill:Destroy()
			stroke.Color = color
			stroke.Thickness = thickness
			stroke.Transparency = transparency
		end)
	end

	local function rarityRim(stroke: UIStroke, style: UIConfig.RarityStyle, thick: number)
		if style.Rainbow then
			rim(stroke, UIConfig.Rainbow, "spin", thick, 2)
		elseif style.Flash then
			rim(stroke, { style.Bottom, style.Top, WHITE, style.Top, style.Bottom }, "sweep", thick, 1.2)
		else
			rim(stroke, { style.Top, style.Bottom, style.Top }, "pulse", thick, 0.9, 0.45)
		end
	end

	local function mutationRim(style: UIConfig.MutationStyle)
		if style.Effect == "rainbow" then
			rim(ui.cardOutline, UIConfig.Rainbow, "spin", 4 / 3, 2)
		else
			local neon = style.Effect == "pulse"
			rim(
				ui.cardOutline,
				{ style.Top, style.Bottom, style.Top },
				"pulse",
				4 / 3,
				if neon then 0.9 else 1.8,
				if neon then 0.6 else 0.3
			)
		end
	end

	--------------------------------------------------------------------------------
	-- Огромное слово редкости (эпическая и выше)
	--------------------------------------------------------------------------------

	-- Волна букв: её твины и флаг «стихла» (после начала полёта в баннер ни одна буква уже не
	-- начинает качаться: таймеры букв его проверяют).
	local titleWave: { tweens: { Tween }, stopped: boolean } = { tweens = {}, stopped = true }

	-- Волна букв стихает: буквы встают на свои места (перед полётом слова в баннер).
	local function stopTitleWave()
		titleWave.stopped = true
		for _, swing in titleWave.tweens do
			swing:Cancel()
		end
		table.clear(titleWave.tweens)
		for _, letter in ui.titleLetters:GetChildren() do
			if letter:IsA("GuiObject") then
				letter.Position = UDim2.fromScale(letter.Position.X.Scale, 0.5)
			end
		end
	end

	-- Спрятать огромное слово: буквы, их волна и блик — прочь.
	local function clearTitle()
		ui.titleSlam.Visible = false
		local ghost = ui.fishing:FindFirstChild("FxTitleMorph") -- слово, тающее в баннер (morphTitle)
		if ghost then
			ghost:Destroy()
		end
		stopTitleWave()
		for _, old in ui.titleLetters:GetChildren() do
			old:Destroy()
		end
		-- Влетая в баннер, слово тает: надпись снова видна (твин нулевой длины отменяет таяние).
		local label = ui.titleLabel
		for _, item in label:GetChildren() do
			if item.Name == "FxShine" then
				item:Destroy()
			end
		end
		UiFx.tween(label, 0, { TextTransparency = 0 })
		label.TextTransparency = 0
		local outline = label:FindFirstChild("Outline")
		if outline and outline:IsA("UIStroke") then
			UiFx.tween(outline, 0, { Transparency = 0 })
			outline.Transparency = 0
		end
	end

	-- Белый блик один раз пробегает слово слева направо (следом за буквами, которые влетают по
	-- одной): поверх каждой надписи — её белая копия FxShine, видна только косая полоса
	-- градиента, она едет с одной скоростью по всему слову. labels — надписи слова (буквы или
	-- одна), их X — в долях слова; time — за сколько полоса проходит слово.
	local function shineTitle(labels: { TextLabel }, time: number)
		local band = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.36, 1),
			NumberSequenceKeypoint.new(0.5, 0.1),
			NumberSequenceKeypoint.new(0.64, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		local speed = 1.2 / math.max(time, 0.05) -- доли слова в секунду (полоса — от −0.1 до 1.1)
		for _, label in labels do
			local x, w = label.Position.X.Scale, math.max(label.Size.X.Scale, 0.01)
			local shine = Instance.new("TextLabel")
			shine.Name = "FxShine"
			shine.BackgroundTransparency = 1
			shine.Size = UDim2.fromScale(1, 1)
			shine.FontFace = label.FontFace
			shine.Text = label.Text
			shine.TextScaled = true
			shine.TextColor3 = WHITE
			shine.TextStrokeTransparency = 1
			shine.ZIndex = label.ZIndex + 1
			local cap = label:FindFirstChildOfClass("UITextSizeConstraint")
			if cap then
				cap:Clone().Parent = shine
			end
			local gradient = Instance.new("UIGradient")
			gradient.Rotation = 15
			gradient.Transparency = band
			gradient.Offset = Vector2.new(-1, 0)
			gradient.Parent = shine
			shine.Parent = label
			-- Полоса (середина градиента) над надписью: Offset −1 → 1 — от её левого края −0.5w до
			-- правого +1.5w.
			local from = math.max((x - 0.5 * w + 0.1) / speed, 0)
			local span = 2 * w / speed
			UiFx.tween(
				gradient,
				span,
				{ Offset = Vector2.new(1, 0) },
				Enum.EasingStyle.Linear,
				Enum.EasingDirection.InOut,
				from
			)
			task.delay(from + span + 0.05, function()
				shine:Destroy()
			end)
		end
	end

	--[[
		Слово (одной надписью или по буквам) — над рыбаком и рыбой над головой (на лучах
		редкости), высотой CLIMAX.TitleHeight экрана (не шире просвета между кнопками), в
		пикселях HUD.Fishing; над рыбой места нет — сбоку от них (см. TitleSide). fish — где на
		экране встанет рыба (её ставит сервер чуть позже слова). Заливка — белое → цвет
		редкости → его тень (мифическая — радуга), толстая обводка; буквы влетают по одной и,
		встав, качаются (волна бежит по слову), следом за ними слово один раз пробегает белый
		блик.
	]]
	local function slamTitle(rarityId: string, reveal: Reveal, style: UIConfig.RarityStyle, fish: Layout.Rect?)
		local text = TITLE_TEXT[rarityId]
		if not text then
			return
		end
		local title = ui.titleSlam
		local rootSize = ui.fishing.AbsoluteSize
		local letters, total = splitLetters(text)
		-- (Не выше TitleMax px: TextScaled в Roblox не крупнее 100 px — выше буквы стояли бы врозь.)
		local height = math.clamp(rootSize.Y * CLIMAX.TitleHeight, 28, CLIMAX.TitleMax)
		-- Не ниже кнопки действия (с зазором) и не шире просвета между кнопками по бокам (и в
		-- начале «удара», когда оно крупнее).
		local middle = rootSize.Y * CLIMAX.TitleY
		local button = ui.actionButton
		local at = button.AbsolutePosition - ui.fishing.AbsolutePosition
		if button.Visible and at.X < (rootSize.X + math.min(total * height, rootSize.X)) / 2 then
			middle = math.max(math.min(middle, at.Y - CARD_SIDE_GAP - height / 2), height / 2)
		end
		-- v3 (WOW-4): над рыбаком и рыбой над головой — руки вверх с трофеем не под буквами (рыбу
		-- сервер ставит чуть позже слова — где она встанет, fish, посчитано заранее).
		local fisher = fisherRect()
		if fisher and fish then
			local pad = Layout.FISHER_PAD
			fisher = Layout.rect(
				math.min(fisher.x0, fish.x0 - pad),
				math.min(fisher.y0, fish.y0 - pad),
				math.max(fisher.x1, fish.x1 + pad),
				fisher.y1
			)
		end
		-- (Сверху — 16 px до верхней панели Roblox: кнопки меню и чата в ней; тесно — выше, но
		-- правее этих кнопок.)
		local bandY, bandH = Layout.topBand(fisher, middle, height, Layout.EDGE, 28)
		local clearLeft = 0
		if not bandY then
			bandY, bandH = Layout.topBand(fisher, middle, height, CARD_TOP_GAP, 28)
			clearLeft = CLIMAX.TopbarRight
		end
		local centerX = rootSize.X / 2
		local wantY, wantH = middle, height -- (желанные: для места сбоку)
		if bandY and bandH then
			middle, height = bandY, bandH
		end
		-- (Полоса слова — с запасом 16 px сверху и снизу: кнопка колонки или прыжка чуть ниже
		-- слова тоже его сужает, а не встаёт вплотную под буквы.)
		local left, right =
			sideLimits(rootSize, middle - height / 2 - CARD_SIDE_GAP, middle + height / 2 + CARD_SIDE_GAP)
		left = math.max(left, clearLeft)
		-- (Ещё 10 px с каждой стороны: обводка букв и их «выскок» Back Out выходят за рамку.)
		local room = 2 * math.max(math.min(centerX - left, right - centerX) - 10, 40)
		if fisher then
			-- v3: над рыбой с трофеем места нет (телефон) — сбоку от них, где просвет шире, на той
			-- же высоте (не выше 16 px от верха): слово рядом с рыбой, а не на ней. v5 (D5): и когда
			-- над ней лишь узкая полоса (планшет, компьютер: слово там мелкое) — сбоку, если там
			-- буквы в CLIMAX.TitleBeside раз крупнее.
			local sideY = math.max(wantY, Layout.EDGE + wantH / 2)
			-- (у колонки справа мешают только показанные кнопки: её пустой верх свободен)
			left, right =
				sideLimits(rootSize, sideY - wantH / 2 - CARD_SIDE_GAP, sideY + wantH / 2 + CARD_SIDE_GAP, true)
			if not UserInputService.TouchEnabled and sideY - wantH / 2 < CLIMAX.ChatBottom then
				left = math.max(left, CLIMAX.ChatRight) -- (окно чата слева вверху)
			end
			local from, to = left, fisher.x0
			if right - fisher.x1 > fisher.x0 - left then
				from, to = fisher.x1, right
			end
			local side = to - from - 20
			local above = if bandY then math.min(height, room / total) else 0
			if side >= total * CLIMAX.TitleSide and math.min(wantH, side / total) > above * CLIMAX.TitleBeside then
				centerX, room, middle, height = (from + to) / 2, side, sideY, wantH
			end
		end
		local width = math.min(total * height, room)
		height = math.min(height, width / total)
		title.AnchorPoint = Vector2.new(0.5, 0.5)
		title.Position = UDim2.fromScale(centerX / math.max(rootSize.X, 1), middle / math.max(rootSize.Y, 1))
		title.Size = UDim2.fromScale(width / math.max(rootSize.X, 1), height / math.max(rootSize.Y, 1))
		clearTitle()
		titleWave.stopped = false
		local single = not reveal.Letters
		-- Как у слова редкости над мини-игрой: белое → цвет редкости → его тень.
		local fill = ColorSequence.new({
			ColorSequenceKeypoint.new(0, WHITE),
			ColorSequenceKeypoint.new(0.45, style.Top),
			ColorSequenceKeypoint.new(1, style.Bottom),
		})
		ui.titleLabel.Visible = single
		UiFx.setText(ui.titleLabel, text)
		local twin = UiFx.twinOf(ui.titleLabel) -- тень слова (у букв её нет)
		if twin then
			twin.Visible = single
		end
		ui.titleSlamFill.Color = fill
		local edge = ui.titleLabel:FindFirstChild("Outline")
		local edgePx = if edge and edge:IsA("UIStroke") then UiFx.strokeThickness(edge) else 5
		local labels: { TextLabel } = { ui.titleLabel }

		if not single then
			-- По букве на надпись: легендарная — золото, мифическая — радуга.
			table.clear(labels)
			local x = 0
			for index, ch in letters do
				local w = letterWidth(ch)
				local letter = Instance.new("TextLabel")
				letter.Name = `L{index}`
				letter.BackgroundTransparency = 1
				letter.FontFace = ui.titleLabel.FontFace
				letter.Text = ch
				letter.TextScaled = true
				letter.TextColor3 = WHITE
				letter.TextStrokeTransparency = 1
				letter.AnchorPoint = Vector2.new(0, 0.5)
				letter.Position = UDim2.fromScale(x / total, 0.5)
				letter.Size = UDim2.fromScale(w / total, 1)
				letter.ZIndex = 2
				local outline = Instance.new("UIStroke")
				outline.Name = "Outline"
				outline.Color = UIConfig.Ink
				outline.Thickness = edgePx -- (как у слова целиком: толстая обводка образца)
				outline.LineJoinMode = Enum.LineJoinMode.Round
				outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
				outline:SetAttribute("BaseThickness", edge and edge:GetAttribute("BaseThickness") or 8)
				outline.Parent = letter
				local gradient = Instance.new("UIGradient")
				gradient.Name = "TextFill"
				gradient.Rotation = 90
				if style.Rainbow then
					letter.TextColor3 = UIConfig.Rainbow[(index - 1) % #UIConfig.Rainbow + 1]
					gradient.Color = ColorSequence.new(WHITE, Color3.fromRGB(215, 215, 215))
				else
					gradient.Color = fill
				end
				gradient.Parent = letter
				letter.Parent = ui.titleLetters
				table.insert(labels, letter)
				x += w
				local landed = CLIMAX.TitleStagger * index
				UiFx.popIn(letter, { from = 0.2, time = 0.24, delay = landed })
				-- Встала — качается вверх-вниз на 6 % высоты слова (Sine; у каждой буквы свой сдвиг
				-- фазы — по слову бежит волна); перед полётом в баннер стихает и уже не начинается.
				later(catchTrove, landed + 0.24, function()
					if titleWave.stopped or letter.Parent == nil then
						return
					end
					local swing = TweenService:Create(
						letter,
						TweenInfo.new(0.32, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
						{ Position = UDim2.fromScale(letter.Position.X.Scale, 0.44) }
					)
					swing:Play()
					table.insert(titleWave.tweens, swing)
				end)
			end
			if style.Rainbow then
				-- Радуга бежит по буквам (один покадровый эффект на все).
				local phase = 0
				catchTrove:Add(UiFx.schedule(function(dt: number): boolean
					phase += dt * 0.8
					for index, letter in labels do
						if letter.Parent == nil then
							return false
						end
						local hue = (index * 0.085 + phase) % 1
						letter.TextColor3 = Color3.fromHSV(hue, 0.7, 1)
					end
					return true
				end))
			end
		end
		title.Visible = true
		local slam = UiFx.scaleOf(title)
		-- (Буквы и так выскакивают по одной — у них «удар» меньше.)
		slam.Scale = math.max(1, math.min(if single then 2.5 else 1.7, room / width))
		UiFx.tween(slam, 0.3, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		if single then
			-- Слово целиком, встав, качается волной (−3° → +3° → 0).
			later(catchTrove, 0.3, function()
				if not titleWave.stopped then
					UiFx.wiggle(title, 3, 2, 0.6)
				end
			end)
		end
		-- Блик — следом за буквами (как встали первые три; одной надписью — когда «удар» сел).
		later(catchTrove, if single then 0.3 else CLIMAX.TitleStagger * 3 + 0.24, function()
			if not titleWave.stopped then
				shineTitle(labels, CLIMAX.Shine)
			end
		end)
		UiFx.sound("swoosh", 0.5, 0.8)
		UiFx.sound("pop", 0.55, 0.9)
		catchTrove:Add(clearTitle)
	end

	-- Слово влетает в баннер карточки (на его надпись «в покое»); на доле CLIMAX.GrowAt полёта
	-- (слово почти на месте) баннер вырастает из него (onGrow; надпись баннера проявляется
	-- следом), а слово тает за 0.08 с — оно «стало» баннером, двух слов сразу не видно. Волна
	-- букв стихает сразу.
	-- Слово летит к месту надписи баннера (Cubic Out: сразу трогается — видно, куда летит, — и
	-- мягко садится). v4: вылетает ещё до карточки (CLIMAX.Lead, полёт CLIMAX.Aim) — к рождению
	-- карточки оно уже у места баннера, карточка растёт под ним снизу (без «наезда» посреди
	-- экрана). title — что двигать (по умолчанию само слово; при передаче — его копия).
	local function aimTitle(time: number, gui: GuiObject?)
		local title = gui or ui.titleSlam
		stopTitleWave()
		local rootSize = ui.fishing.AbsoluteSize
		local pos, size = cardRect(ui.rarityLabel)
		local _, total = splitLetters(ui.titleLabel.Text)
		local h = size.Y * 1.05
		local w = math.min(total * h, size.X * 1.15)
		h = math.min(h, w / total)
		local center = pos + size / 2
		UiFx.tween(title, time, {
			Position = UDim2.fromScale(center.X / math.max(rootSize.X, 1), center.Y / math.max(rootSize.Y, 1)),
			Size = UDim2.fromScale(w / math.max(rootSize.X, 1), h / math.max(rootSize.Y, 1)),
		}, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
	end

	-- v4: с рождением карточки слово — уже переход, эффект: виджет слова убран, его копия
	-- FxTitleMorph (как призрак FxCardOut у закрытия) досаживается в баннер за долю GrowAt и
	-- тает в нём. Пропуск (clearTitle) убирает и копию — баннер тогда встаёт сам.
	local function morphTitle(time: number, onGrow: () -> ())
		local title = ui.titleSlam
		if not title.Visible then
			onGrow()
			return
		end
		stopTitleWave()
		local ghost = title:Clone()
		ghost.Name = "FxTitleMorph"
		for _, item in ghost:GetDescendants() do
			if item.Name == "FxShine" then
				item:Destroy()
			end
		end
		UiFx.tween(title, 0, { Position = title.Position, Size = title.Size }) -- полёт виджета — прочь
		clearTitle()
		ghost.Parent = title.Parent
		catchTrove:Add(ghost)
		local growAt = time * CLIMAX.GrowAt
		aimTitle(growAt, ghost)
		later(catchTrove, growAt, function()
			if not ui.card.Visible or ghost.Parent == nil then
				return
			end
			for _, item in ghost:GetDescendants() do
				if item:IsA("TextLabel") then
					UiFx.tween(item, 0.08, { TextTransparency = 1 })
				elseif item:IsA("UIStroke") then
					UiFx.tween(item, 0.08, { Transparency = 1 })
				end
			end
			onGrow()
		end)
		later(catchTrove, growAt + 0.1, function()
			ghost:Destroy()
		end)
	end

	--------------------------------------------------------------------------------
	-- Победа в мини-игре и ожидание приземления
	--------------------------------------------------------------------------------

	-- Когда мини-игра последний раз появилась: "Caught" бывает только после неё, но атрибут
	-- FishingState = "Idle" может обогнать событие и спрятать панель раньше — копия всё равно нужна.

	-- (Вложенный блок: winWord нужен только winGhost — регистры раздела не тратятся.)
	do
		-- «ПОЙМАНА!» — самое громкое слово мини-игры — влетает ударом (2.4 → 1, доворот) левее и ниже
		-- середины экрана, там, где нет прыжка рыбы (он идёт от поплавка правее головы вверх, к
		-- голове); вокруг расходится кольцо. Цвет по редкости: обычная и редкая — зелёное, эпическая —
		-- виноградное, легендарная — золото, мифическая — бегущая радуга. По высоте — середина панели;
		-- в своей полосе — не на своём рыбаке и не ближе 16 px к джойстику и кнопкам (sideLimits), не
		-- влезает — ниже ростом (UX-02); «удар» растёт от края, дальнего от рыбака и джойстика
		-- (FishingLayout.slamPivot, UX-03): и в начале он их не закрывает.
		local function winWord(rarityId: string, panel: GuiObject)
			local colors: { [string]: { Color3 } } = {
				Epic = { Palette.Grape.Top, Palette.Grape.Bottom },
				Legendary = { Palette.Gold.Top, Palette.Gold.Bottom },
				Mythic = UIConfig.Rainbow,
			}
			local style = UIConfig.Rarity[rarityId] or UIConfig.Rarity.Common
			local hud = ui.hud
			local root = ui.fishing.AbsoluteSize -- (раскладка — в px HUD.Fishing)
			local shift = ui.fishing.AbsolutePosition - hud.AbsolutePosition
			local textHeight = math.clamp(hud.AbsoluteSize.Y * CLIMAX.WinHeight, 56, 96)
			local cy = panel.AbsolutePosition.Y - ui.fishing.AbsolutePosition.Y + panel.AbsoluteSize.Y * 0.5
			local left, right = sideLimits(root, cy - textHeight / 2, cy + textHeight / 2)
			local want = math.max(root.X * 0.42 - textHeight * 2.6, left + textHeight * 2.6)
			local fisher = fisherRect()
			local keepouts = { thumbstickBox(root) }
			if fisher then
				table.insert(keepouts, fisher)
				if fisher.y0 < cy + textHeight / 2 and fisher.y1 > cy - textHeight / 2 then
					if (fisher.x0 + fisher.x1) / 2 >= want then
						right = math.min(right, fisher.x0 - 8)
					else
						left = math.max(left, fisher.x1 + 8)
					end
				end
			end
			local width = math.clamp(right - left, CLIMAX.WinLeast * 5.2, textHeight * 5.2)
			textHeight = width / 5.2
			local cx =
				math.clamp(root.X * 0.42 - width / 2, left + width / 2, math.max(left + width / 2, right - width / 2))
			local rest = Layout.rect(cx - width / 2, cy - textHeight / 2, cx + width / 2, cy + textHeight / 2)
			local pivot, from = Layout.slamPivot(rest, 2.4, keepouts)
			local label = UiFx.floatText(hud, WIN_TEXT, {
				position = offset(rest.x0 + pivot.X * width + shift.X, cy + shift.Y),
				anchor = pivot,
				size = offset(width, textHeight),
				colors = colors[rarityId] or { Palette.Leaf.Top, Palette.Leaf.Bottom },
				rise = 0.04,
				time = CLIMAX.WinTime,
				rotate = -6,
				z = 30,
			})
			local outline = label:FindFirstChild("Outline")
			if outline and outline:IsA("UIStroke") then
				outline.Thickness = math.max(UIConfig.Fx.TextStrokeMin, math.round(textHeight * 0.045))
			end
			local scale = label:FindFirstChildOfClass("UIScale")
			if scale then
				scale.Scale = from
				UiFx.tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			end
			local fill = label:FindFirstChild("TextFill")
			if style.Rainbow and fill and fill:IsA("UIGradient") then
				-- Радуга вдоль букв и бежит по ним.
				fill.Rotation = 0
				fill.Offset = Vector2.new(-0.25, 0)
				UiFx.tween(
					fill,
					CLIMAX.WinTime,
					{ Offset = Vector2.new(0.25, 0) },
					Enum.EasingStyle.Sine,
					Enum.EasingDirection.InOut
				)
			end
			-- Кольцо-«пилюля» вокруг слова расходится, когда удар сел (не дальше рыбака и джойстика).
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = label
			local _, ring = Layout.slamPivot(rest, 1.35, keepouts, true)
			task.delay(0.12, function()
				if label.Parent then
					UiFx.glowRing(label, {
						color = if style.Rainbow then WHITE else style.Top,
						scale = math.max(ring, 1.1),
						thickness = 4,
						time = 0.45,
					})
				end
			end)
		end

		-- Копия мини-игры «побеждает»: последний ⭐ печатается, зона вспыхивает золотом, стрелка — где
		-- нажали, искры, «ПОЙМАНА!»; через 0.12 с подпрыгивает и уходит вниз (сжимается, тает) — не
		-- закрывает рыбу, которая выпрыгивает из воды. Панель могла уже спрятаться (атрибут
		-- FishingState обогнал событие) — копия всё равно видна.
		function winGhost(rarityId: string)
			local source = ui.minigame
			if not source.Visible and os.clock() - minigameShownAt > FishingConfig.MinigameTimeout + 1 then
				return
			end
			local style = UIConfig.Rarity[rarityId] or UIConfig.Rarity.Common
			local ghost = ghostOf(source, "FxMinigameWin")

			-- Последний нужный кружок попадания (сколько их видно) — с ⭐.
			local pips = ghost:FindFirstChild("Pips")
			local last = 1
			for index = 1, 5 do
				local candidate = pips and pips:FindFirstChild(`Pip{index}`)
				if candidate and candidate:IsA("GuiObject") and candidate.Visible then
					last = index
				end
			end
			local pip = pips and pips:FindFirstChild(`Pip{last}`)
			if pip and pip:IsA("GuiObject") then
				pip.BackgroundColor3 = COLORS.PipDone
				local star = pip:FindFirstChild("Star")
				if star and star:IsA("TextLabel") then
					star.TextTransparency = 0
					local scale = UiFx.scaleOf(star)
					scale.Scale = 2
					UiFx.tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				end
			end
			local track = ghost:FindFirstChild("Track")
			local zone = track and track:FindFirstChild("Zone")
			local flash = zone and zone:FindFirstChild("Flash")
			local needle = track and track:FindFirstChild("Needle")
			local zoneX = if zone and zone:IsA("GuiObject") then zone.Position.X.Scale else 0.5
			local origin = Vector2.new(defaults.trackLeft + zoneX * defaults.trackWidth, defaults.trackMidY)
			if flash and flash:IsA("GuiObject") then
				flash.BackgroundColor3 = Palette.Gold.Top
				flash.BackgroundTransparency = 0.05
				UiFx.tween(flash, 0.3, { BackgroundTransparency = 1 })
			end
			if needle and needle:IsA("GuiObject") and tapNeedle then
				-- Стрелка — где было победное нажатие (сервер судил по нему), а не где она сейчас.
				needle.Position = UDim2.fromScale(tapNeedle, needle.Position.Y.Scale)
				needle.BackgroundColor3 = Palette.Gold.Top
			end
			UiFx.burst(ghost, {
				origin = origin,
				count = 32,
				colors = { style.Top, WHITE, Palette.Gold.Top },
				power = 1.7,
				z = 9,
			})
			winWord(rarityId, source)
			UiFx.sound("pop", 0.55, 1.25)

			task.delay(0.12, function()
				if ghost.Parent == nil then
					return
				end
				UiFx.bump(ghost, 1.05, 0.12)
				task.delay(0.08, function()
					if ghost.Parent == nil then
						return
					end
					local quad, inward = Enum.EasingStyle.Quad, Enum.EasingDirection.In
					UiFx.tween(UiFx.scaleOf(ghost), 0.2, { Scale = 0.6 }, quad, inward)
					UiFx.tween(ghost, 0.2, { Position = ghost.Position + UDim2.fromScale(0, 0.06) }, quad, inward)
					UiFx.fadeOut(ghost, 0.2)
					task.delay(0.22, function()
						ghost:Destroy()
					end)
				end)
			end)
		end
	end

	-- Точка над головой своего персонажа (если сигнала с точкой рыбы нет).
	local function headPoint(): Vector3?
		local character = player.Character
		local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
		if head and head:IsA("BasePart") then
			return head.Position + Vector3.new(0, 2.5, 0)
		end
		return nil
	end

	-- Точка мира на экране в пикселях HUD.Fishing (в пределах экрана), или nil — не видно.
	local function screenPoint(world: Vector3?): Vector2?
		local camera = Workspace.CurrentCamera
		if not camera or not world then
			return nil
		end
		local point, onScreen = camera:WorldToScreenPoint(world)
		if not onScreen or point.Z <= 0 then
			return nil
		end
		local root = ui.fishing
		local local2 = Vector2.new(point.X, point.Y) - root.AbsolutePosition
		local size = root.AbsoluteSize
		return Vector2.new(
			math.clamp(local2.X, size.X * 0.08, size.X * 0.92),
			math.clamp(local2.Y, size.Y * 0.1, size.Y * 0.85)
		)
	end

	--------------------------------------------------------------------------------
	-- Доли карточки, пропуск, закрытие
	--------------------------------------------------------------------------------

	local function addBeat(at: number, run: (instant: boolean) -> ())
		local beat = { at = at, run = run, done = false }
		table.insert(cardBeats, beat)
		later(cardTrove, at, function()
			if not beat.done then
				beat.done = true
				run(false)
			end
		end)
	end

	-- Тап до последней доли: всё оставшееся — сразу в конечном виде, карточка подпрыгивает и
	-- CLIMAX.SkipDwell не закрывается — её успевают разглядеть целиком («замок» тапов tapCard
	-- продлевается: как будто карточка только что открылась).
	local function skipBeats()
		cardOpenedAt = os.clock() + CLIMAX.SkipDwell - CARD_INPUT_LOCK
		for _, beat in cardBeats do
			if not beat.done then
				beat.done = true
				beat.run(true)
			end
		end
		for _, hook in skipHooks do
			hook()
		end
		UiFx.bump(ui.card, 1.06, 0.25)
	end

	-- Карточка уходит: она сама — снаряд. Её копия летит в кнопку «САДОК» (Этап 3; Quad In: на
	-- CARD.Reach пути, сжимаясь до CARD.Shrink, чуть поворачиваясь) и тает в самом конце; через
	-- CARD.Fly рядом с ней вылетают 🐟 и ★ (flyHome) — долетают вместе. Рыба продана сразу (садок
	-- полон, Tank.Result "sold") — в кошелёк, и летит 💵; кнопки нет (нет базы) — в середину
	-- колонки кнопок (CatchFx.flyTarget).
	local function ghostCard(): GuiObject
		local ghost = ui.card:Clone()
		ghost.Name = "FxCardOut"
		ghost.Active = false
		pcall(function()
			(ghost :: any).Interactable = false -- копия не ловит нажатия (где свойство есть)
		end)
		for _, item in ghost:GetDescendants() do
			if item.Name == "FxSparkle" or item.Name == "FxRing" or item.Name == "FxGlitter" then
				item:Destroy() -- застывшие звёздочки и кольца выглядят странно
			end
		end
		local viewport = ghost:FindFirstChild("Viewport")
		local camera = viewport and viewport:FindFirstChildOfClass("Camera")
		if viewport and viewport:IsA("ViewportFrame") and camera then
			viewport.CurrentCamera = camera
		end
		ghost.Parent = ui.card.Parent
		local origin = ui.fishing.AbsolutePosition
		local aim = CatchFx.flyTarget(ui.counter, ui.wallet, cardTank)
		local target = aim.AbsolutePosition + aim.AbsoluteSize / 2 - origin
		local box = cardBox
		local from = if box then box.center else ghost.AbsolutePosition + ghost.AbsoluteSize / 2 - origin
		local to = from:Lerp(target, CARD.Reach)
		local quad, inward = Enum.EasingStyle.Quad, Enum.EasingDirection.In
		local travel = CARD.Travel
		UiFx.tween(ghost, travel, { Position = offset(to.X, to.Y), Rotation = 8 }, quad, inward)
		UiFx.tween(UiFx.scaleOf(ghost), travel, { Scale = CARD.Shrink }, quad, inward)
		task.delay(travel * 0.65, function()
			if ghost.Parent then
				UiFx.fadeOut(ghost, travel * 0.35)
			end
		end)
		task.delay(travel + 0.04, function()
			ghost:Destroy()
		end)
		return ghost
	end

	-- 🐟 прилетела: рыба в садке (CounterHold снят), через 0.15 с кнопка снова «ЗАБРОСИТЬ», ещё
	-- через CLIMAX.Trophy свой трофей над головой «вспыхивает» ещё раз — карточка его больше не
	-- закрывает, а «+1» уже встал (два удара не в один миг): FishingFxController.ReplayOwnTrophy
	-- (шар, ореол, табличка выскакивает впервые — до того её прятала карточка, искры).
	local function finishCatch(serial: number, animate: boolean)
		releaseCounter(serial)
		if serial ~= catchSerial or not catchScreen then
			return
		end
		if animate then
			later(celebrationTrove, CLIMAX.Trophy, function()
				local module = script.Parent and script.Parent:FindFirstChild("FishingFxController")
				local ok, fx = pcall(function(): any
					return if module and module:IsA("ModuleScript") then require(module) :: any else nil
				end)
				if ok and fx and type(fx.ReplayOwnTrophy) == "function" then
					pcall(fx.ReplayOwnTrophy)
				end
			end)
		end
		catchScreen = false
		unfadeGroup(ui.status, STATUS_FADE) -- обычно уже вернулись с карточкой (подстраховка)
		unfadeGroup(ui.actionButton, 0) -- сразу: вид кнопки ставит refreshButtons (а «выскок» скрывает смену)
		refreshButtons()
		local button = ui.actionButton
		if animate and button.Visible then
			UiFx.popIn(button, { from = 0.3, time = 0.35 })
			whiteRings(0, true) -- (кольцо не дотягивается до кнопки прыжка: D4)
		end
		refreshContextHint()
	end

	-- 🐟 (рыба продана сразу — 💵) вылетает из летящей карточки (рядом с местом, откуда она
	-- стартовала) в кнопку «САДОК» (или в кошелёк), следом — ★ цветов редкости (мифическая —
	-- радуга); на месте кнопка «встречает» её (TankButtonController, цвет — CounterIncoming;
	-- кошелёк считает монеты — MoneyController). Откуда — запоминается один раз: невидимая «точка
	-- старта» FxFlyFrom живёт, пока не вылетит последняя ★ (сама карточка к тому времени уже
	-- удалена — её Absolute* устарели бы).
	local function flyHome(from: GuiObject, reveal: Reveal, serial: number)
		local hud = ui.hud
		local height = math.max(hud.AbsoluteSize.Y, 1)
		local fishPx = math.max(28, height * 0.075) -- 🐟 ≈ 28 px на телефоне, крупнее на больших
		local counter = CatchFx.flyTarget(ui.counter, ui.wallet, cardTank)
		local start = Instance.new("Frame")
		start.Name = "FxFlyFrom"
		start.BackgroundTransparency = 1
		start.AnchorPoint = Vector2.new(0.5, 0.5)
		start.Size = UDim2.fromOffset(2, 2)
		start.Position = offset(
			from.AbsolutePosition.X + from.AbsoluteSize.X / 2 - hud.AbsolutePosition.X,
			from.AbsolutePosition.Y + from.AbsoluteSize.Y / 2 - hud.AbsolutePosition.Y
		)
		start.Parent = hud
		celebrationTrove:Add(start)
		celebrationTrove:Add(UiFx.flyTo(hud, start, counter, {
			text = CatchFx.flyIcon(cardTank),
			time = CARD.FishTime,
			size = fishPx / height,
			arc = 0.12,
			onArrive = function()
				releaseCounter(serial) -- рыба в садке (её «прилёт» играет TankButtonController)
				UiFx.sound("pop", 0.35, 1.2)
				task.delay(0.15, finishCatch, serial, true)
			end,
		}))
		-- ★ — одной стайкой (один покадровый эффект: бюджет полёта — не больше трёх): разлетаются
		-- из карточки и летят друг за другом, на прилёте каждой — «тик» всё выше.
		local style = UIConfig.Rarity[reveal.Id] or UIConfig.Rarity.Common
		if reveal.Trail > 0 then
			celebrationTrove:Add(UiFx.flyTo(hud, start, counter, {
				text = "★",
				color = if style.Rainbow then UIConfig.Rainbow[5] else style.Top,
				count = reveal.Trail,
				gap = CARD.StarGap * 2,
				time = CARD.FishTime,
				size = fishPx * 0.55 / height,
				arc = 0.12,
				onEach = function(index: number)
					UiFx.sound("tick", 0.18, 1.15 + 0.06 * index)
				end,
			}))
		end
		start:Destroy() -- (откуда лететь, flyTo запомнил сразу)
	end

	local function closeCard()
		local card = ui.card
		if not card.Visible then
			return
		end
		local serial = catchSerial
		local reveal = cardReveal
		local ghost = ghostCard()
		cardTrove:Clean()
		card.Visible = false
		cardSettled = true
		clearTitle()
		-- Кнопка снова «замирает» (тусклое «ЖДЁМ…», без ореола), пока 🐟 не долетит: сначала вид,
		-- потом гашение (иначе твин гашения вернул бы ореол «ЗАБРАТЬ!»).
		refreshButtons()
		fadeGroup(ui.actionButton, BUTTON_FADE, 0.15)

		-- Лучи сжимаются вместе с карточкой, затемнение тает.
		for _, holder in ui.rays:GetChildren() do
			if holder.Name == "FxRays" and holder:IsA("GuiObject") then
				UiFx.tween(UiFx.scaleOf(holder), 0.2, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
		end
		later(raysTrove, 0.22, function()
			raysTrove:Clean()
		end)
		local dim = ui.dim
		dimTo(1, DIM_TIME * 0.8)
		later(celebrationTrove, DIM_TIME * 0.8, function()
			if not ui.card.Visible then
				dim.Visible = false
			end
		end)
		-- Цель полёта — кнопка «САДОК» (или кошелёк): плашки статуса возвращаются сразу, кнопка
		-- знает, что к ней летит (CounterIncoming — редкость: прилёт в её цветах).
		-- Через CARD.Fly за ней — 🐟 (трофей над головой «вспыхнет», когда она долетит: finishCatch).
		unfadeGroup(ui.status, STATUS_FADE)
		if heldSerial == serial then
			ui.hud:SetAttribute("CounterIncoming", reveal.Id)
		end
		later(celebrationTrove, CARD.Fly, function()
			flyHome(ghost, reveal, serial)
		end)
		UiFx.sound("swoosh", 0.3)
	end

	-- Тап по карточке: до неё — ничего (рыба ещё летит), в первые CARD_INPUT_LOCK — ничего
	-- (лишний тап после победного), до последней доли — пропуск, потом — закрыть (но не раньше
	-- CLIMAX.SkipDwell после пропуска: двойной тап её не прячет). Действие (кнопка, F / R2,
	-- удочка; sinceAction — сколько секунд прошло с прошлого) долей не пропускает: «ЛОВИ!» жмут
	-- по инерции и после победы. Оно только закрывает показанную целиком карточку («ЗАБРАТЬ!») и
	-- только после паузы CARD.Mash — пока жмут подряд, карточка стоит.
	function tapCard(sinceAction: number?)
		if not catchScreen or not ui.card.Visible then
			return
		end
		if os.clock() - cardOpenedAt < CARD_INPUT_LOCK then
			return
		end
		if sinceAction and (not cardSettled or sinceAction < CARD.Mash) then
			return
		end
		if cardSettled then
			closeCard()
		else
			skipBeats()
		end
	end

	-- «Печать» из from: масштаб from → 1 и доворот rotate → место (Back Out).
	local function stampIn(gui: GuiObject, from: number, rotate: number, time: number)
		local scale = UiFx.scaleOf(gui)
		scale.Scale = from
		UiFx.tween(scale, time, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		local rest = gui.Rotation
		gui.Rotation = rest + rotate
		UiFx.tween(gui, time, { Rotation = rest }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end

	-- Цена набегает от from до to мягко (1 − (1 − k)^1.6: цифры бегут до самого «приземления», за
	-- 0.15 с до него — не больше ≈ 92 %); тик — только когда число сменилось, не чаще 20 раз
	-- в секунду, тон растёт pitchFrom → pitchTo. Возвращает stop (сразу конечное число).
	local function countPrice(from: number, to: number, time: number, pitchFrom: number, pitchTo: number): () -> ()
		local label = ui.priceLabel
		local shown = math.floor(from + 0.5)
		label.Text = CatchFx.money(shown)
		local elapsed = 0
		local lastTick = -math.huge
		return UiFx.schedule(function(dt: number): boolean
			elapsed += dt
			local k = math.min(1, elapsed / math.max(time, 0.01))
			local eased = 1 - (1 - k) ^ 1.6
			local value = math.floor(from + (to - from) * eased + 0.5)
			if value ~= shown then
				shown = value
				label.Text = CatchFx.money(value)
				if elapsed - lastTick >= 1 / 12 then
					-- Тик и «подскок» числа (1.06 → 1) — не чаще 12 раз в секунду: «число растёт».
					lastTick = elapsed
					UiFx.sound("tick", 0.18, pitchFrom + (pitchTo - pitchFrom) * k)
					UiFx.bump(label, 1.06, 0.1)
				end
			end
			return k < 1
		end, function()
			label.Text = CatchFx.money(to)
		end)
	end

	-- Дождь 💰 сверху экрана, когда цена «приземлилась» (легендарная и мифическая): монеты падают
	-- по бокам от карточки и за ней (слой HUD.Fishing под карточкой, над затемнением и лучами) —
	-- на имя и цену не падают. Появляются (тают в видимость) в Layout.EDGE px под верхом HUD — не в
	-- ряду кнопок меню и чата Roblox (SIMC-C2-03). Только твины.
	local function coinRain(count: number, time: number)
		local rootSize = ui.fishing.AbsoluteSize
		local box = cardBox
		local x0, x1 = 0.5, 0.5 -- карточка (с запасом), доли ширины
		if box then
			x0 = (box.center.X - box.size.X * 0.6) / math.max(rootSize.X, 1)
			x1 = (box.center.X + box.size.X * 0.6) / math.max(rootSize.X, 1)
		end
		local leftRoom, rightRoom = math.max(x0 - 0.03, 0), math.max(0.97 - x1, 0)
		if box and box.dock then
			-- (UI v5: карточка сбоку от рыбака — 💰 падают с её внешней стороны и за ней, но не
			-- ближе 0.3 её ширины к рыбаку с трофеем)
			local inner = (box.center.X + box.dock * box.size.X * 0.2) / math.max(rootSize.X, 1)
			if box.dock < 0 then
				leftRoom, rightRoom = math.max(inner - 0.03, 0), 0
			else
				leftRoom, rightRoom, x1 = 0, math.max(0.97 - inner, 0), inner
			end
		end
		local rng = Random.new()
		for index = 1, count do
			local coin = Instance.new("TextLabel")
			coin.Name = "FxCoin"
			coin.BackgroundTransparency = 1
			coin.Text = "💰"
			coin.TextScaled = true
			coin.AnchorPoint = Vector2.new(0.5, 0.5)
			coin.SizeConstraint = Enum.SizeConstraint.RelativeYY
			coin.Size = UDim2.fromScale(0.075, 0.075)
			local x = rng:NextNumber(0.08, 0.92)
			if leftRoom + rightRoom > 0.08 then
				local u = rng:NextNumber(0, leftRoom + rightRoom)
				x = if u < leftRoom then 0.03 + u else x1 + (u - leftRoom)
			end
			coin.Position = UDim2.new(x, 0, 0.0375, Layout.EDGE)
			coin.Rotation = rng:NextNumber(-30, 30)
			coin.ZIndex = ui.card.ZIndex - 2
			coin.TextTransparency = 1
			coin.Parent = ui.fishing
			celebrationTrove:Add(coin)
			local fall = time * rng:NextNumber(0.7, 1)
			local wait = (index - 1) * time * 0.035
			UiFx.tween(coin, 0.12, { TextTransparency = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, wait)
			UiFx.tween(coin, fall, {
				Position = UDim2.fromScale(x + rng:NextNumber(-0.025, 0.025), 1.1),
				Rotation = coin.Rotation + rng:NextNumber(-220, 220),
			}, Enum.EasingStyle.Quad, Enum.EasingDirection.In, wait)
			task.delay(wait + fall + 0.05, function()
				coin:Destroy()
			end)
		end
	end

	-- Мифическая: после последней доли вокруг карточки медленно всплывают и тают ✨.
	local function glitter(count: number)
		local card = ui.card
		local rng = Random.new()
		for index = 1, count do
			local star = Instance.new("TextLabel")
			star.Name = "FxGlitter"
			star.BackgroundTransparency = 1
			star.Text = if index % 3 == 0 then "⭐" else "✨"
			star.TextScaled = true
			star.AnchorPoint = Vector2.new(0.5, 0.5)
			star.SizeConstraint = Enum.SizeConstraint.RelativeYY
			star.Size = UDim2.fromScale(0.09, 0.09)
			local side = index % 4
			local x = if side == 0 then -0.03 elseif side == 1 then 1.03 else rng:NextNumber(0.05, 0.95)
			local y = if side == 2 then -0.04 elseif side == 3 then 1.02 else rng:NextNumber(0.1, 0.9)
			star.Position = UDim2.fromScale(x, y)
			star.ZIndex = 9
			star.Parent = card
			cardTrove:Add(star)
			local scale = UiFx.scaleOf(star)
			scale.Scale = 0
			local wait = (index - 1) * 0.22
			UiFx.tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, wait)
			UiFx.tween(
				star,
				2.2,
				{ Position = UDim2.fromScale(x, y - 0.12), Rotation = rng:NextNumber(-40, 40) },
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.Out,
				wait
			)
			UiFx.tween(star, 0.8, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, wait + 1.4)
			task.delay(wait + 2.25, function()
				star:Destroy()
			end)
		end
	end

	--------------------------------------------------------------------------------
	-- Карточка: открытие и доли
	--------------------------------------------------------------------------------

	-- Лучи цветов редкости в слое CatchRays: за карточкой (placeCard уже поставил её на место) или
	-- у слова редкости — в точке рыбы над головой at, с пустой серединой hole; растут из центра и
	-- крутятся; второе кольцо навстречу — у легендарной и мифической или цветами мутации. На
	-- тач-экране лучей меньше (REVEAL.TouchRays) и они короче (MaxPx; на маленьком телефоне ещё
	-- короче, вместе с карточкой: заливка), без ореолов, «дыхания» и свечения в центре (оно под
	-- карточкой); на компьютере — не больше CARD.DesktopRays × MaxPx. За карточкой — не меньше
	-- CatchFx.RAYS_MIN её высот (UI v5, SIMC-C1-01: у карточки сбоку от рыбака они не короче, а
	-- обрезаны у его края — CatchFx.raysFrame: до рыбака с трофеем не достают). look —
	-- «громкость» (новый вид — свой праздник), colors — цвета лучей (по умолчанию — редкости).
	local function startRays(
		fish: FishingRules.FishData,
		hole: number?,
		look: Reveal?,
		colors: { Color3 }?,
		clear: number?,
		at: Vector2?
	): { serial: number, main: UiFx.Rays, extra: UiFx.Rays?, card: boolean }
		raysTrove:Clean()
		local style = UIConfig.Rarity[fish.Rarity] or UIConfig.Rarity.Common
		local reveal = look or REVEAL[fish.Rarity] or REVEAL.Common
		local mutationStyle = if fish.Mutation then UIConfig.Mutations[fish.Mutation] else nil
		local touch = UserInputService.TouchEnabled
		local box = cardBox
		local small = if box then math.clamp(box.slot / CARD.RefHeight, 0.7, 1) else 1
		local maxPx = if touch then reveal.MaxPx * small else reveal.MaxPx * CARD.DesktopRays
		local height = if box then box.size.Y else 200
		local across = CatchFx.raysSize(reveal.Size, height, maxPx, hole ~= nil)
		if hole and clear then
			-- (v5: пустая середина — не меньше трофея, clear px от центра лучей: огромную рыбу на
			-- маленьком телефоне спицы не перечёркивают)
			hole = math.max(hole, clear / math.max(across / 2, 1))
		end
		-- Слой лучей: у карточки рядом с рыбаком — до его края (лучи у него обрезаны), у слова — весь.
		CatchFx.raysFrame(ui.rays, ui.fishing.AbsoluteSize, if box and not hole then box.clip else nil)
		local center = at or (if box then box.center else ui.fishing.AbsoluteSize / 2)
		ui.rays.Visible = true
		local main = raysTrove:Add(UiFx.rays(ui.rays, {
			colors = colors or style.Rays,
			count = if touch then reveal.TouchRays else reveal.Rays,
			speed = reveal.Speed,
			size = reveal.Size,
			maxPx = across,
			-- сцена слова (hole): тонкие лучи-спицы, прозрачнее — удар в точке рыбы не заливается
			-- (CLIMAX.TitleRays); за карточкой — обычные
			width = if hole then CLIMAX.TitleRays.Width else nil,
			transparency = if hole then math.min(reveal.Alpha + CLIMAX.TitleRays.Fade, 0.85) else reveal.Alpha,
			glow = not touch,
			grow = 0.5,
			hole = hole,
			growFrom = if hole then 0.75 else 0, -- середина пустая с первого кадра
		}))
		CatchFx.aimRays(main.holder, ui.rays, center, across)
		local extraColors: { Color3 }? = if reveal.Extra then style.Rays else nil
		if mutationStyle then
			extraColors = if mutationStyle.Effect == "rainbow"
				then UIConfig.Rainbow
				else { mutationStyle.Top, mutationStyle.Bottom }
		end
		local extra: UiFx.Rays? = nil
		if extraColors then
			local wider = CatchFx.raysSize(reveal.Size * 1.2, height, maxPx * 1.12, hole ~= nil)
			local ring = raysTrove:Add(UiFx.rays(ui.rays, {
				colors = extraColors,
				count = if touch then 6 else 8,
				speed = -reveal.Speed * 0.6,
				size = reveal.Size * 1.2,
				maxPx = wider,
				width = if hole then CLIMAX.TitleRays.Width * 0.6 else 0.045,
				transparency = math.min(reveal.Alpha + 0.2 + (if hole then CLIMAX.TitleRays.Fade else 0), 0.88),
				glow = false,
				halo = false,
				breathe = false,
				grow = 0.6,
				hole = hole,
				growFrom = if hole then 0.75 else 0,
			}))
			CatchFx.aimRays(ring.holder, ui.rays, center, wider)
			extra = ring
		end
		local current = { serial = catchSerial, main = main, extra = extra, card = hole == nil }
		cardRays = current
		raysTrove:Add(function()
			ui.rays.Visible = false
			if cardRays == current then
				cardRays = nil
			end
		end)
		return current
	end

	--[[
		Карточка открылась (c): рождается в точке рыбы и встаёт на место (позиция — Quint Out, без
		перелёта за место; масштаб — «печать» с доворотом), имя — вместе с ней (въезжает справа,
		Quint Out: правая половина не пустует). Доли — по одной, не ближе REVEAL.Beat друг к
		другу, у каждой своё движение: редкость (огромное слово влетает в баннер и баннер
		вырастает из него; без слова баннер «раскатывается» из середины) → «НОВИНКА!» (штамп, Back
		Out — только штампы пружинят; новый вид обычной и редкой — искры, конфетти, «дзынь») → вес
		и цена (поднимаются, Quad Out, цена на CARD.Chips позже) → цена набегает и «приземляется»
		(фишка сплющивается и пружинит, Elastic; из неё вылетает «+$4/с» — CARD.PriceFloat; у
		легендарной и мифической — дождь 💰 и конфетти, у мифической — радужные края экрана и
		тряска) → мутация (через долю: штамп, «×N», пересчёт — праздник цены тогда у полной цены,
		а первая «приземляется» тихо) → подсказка «Тапни — забрать!» и кнопка «ЗАБРАТЬ!»;
		мифическая потом «дышит» и покачивается. Редкость видна и на самой карточке: маленькие
		лучи за рыбой, у эпической и выше — «живая» обводка, у легендарной и мифической — лицо в
		цвет редкости (мифическая — пастельная радуга).
	]]
	local function openCard(fish: FishingRules.FishData, from: Vector2?)
		cardTrove:Clean()
		table.clear(cardBeats)
		table.clear(skipHooks)
		cardSettled = false
		cardOpenedAt = os.clock()

		local style = UIConfig.Rarity[fish.Rarity] or UIConfig.Rarity.Common
		local reveal = REVEAL[fish.Rarity] or REVEAL.Common
		local mutationStyle = if fish.Mutation then UIConfig.Mutations[fish.Mutation] else nil
		local mutation = if fish.Mutation then FishingRules.GetMutation(fish.Mutation) else nil
		local mutated = mutationStyle ~= nil and mutation ~= nil -- штамп мутации и пересчёт цены
		local card = ui.card
		-- (Этап 3: «НОВИНКА!» — первый улов вида за всё время, Fish.New от сервера; нет — за игру)
		local isNew = if fish.New ~= nil then fish.New else not seenSpecies[fish.Id]
		seenSpecies[fish.Id] = true
		-- Новый вид обычной или редкой рыбы (первый улов новичка чаще всего такой) — маленький
		-- праздник (CARD.New): лучи ярче, с зеленью и золотом, лёгкое затемнение, «+$4/с», у штампа
		-- «НОВИНКА!» — искры, конфетти и «дзынь». Знакомая обычная рыба — спокойная.
		local fanfare = isNew and not reveal.Title
		if fanfare then
			local loud = table.clone(reveal)
			local spec = CARD.New
			loud.Float = math.max(loud.Float, spec.Float)
			loud.Alpha = math.min(loud.Alpha, spec.Alpha)
			loud.Size = math.max(loud.Size, spec.Size)
			loud.MaxPx = math.max(loud.MaxPx, spec.MaxPx)
			loud.Dim = math.min(loud.Dim, spec.Dim)
			reveal = loud
		end
		cardReveal = reveal

		-- (у слова место уже выбрано на приземлении — порог «сбоку» тот же, CARD.DockSlack)
		placeCard(reveal.Scale, fishBox(fish), if reveal.Title then CARD.DockSlack else nil, reveal)
		fillCard(fish, style)
		showFishModel(fish)
		card.Visible = true
		ui.rays.Visible = true
		local box = cardBox :: {
			center: Vector2,
			size: Vector2,
			wide: boolean,
			slot: number,
			dock: number?,
			edge: number?,
			clip: Layout.Rect?,
		}
		-- Где доли стоят «в покое» (после раскладки): к этому они едут и пружинят.
		local rest = {
			banner = ui.banner.Size,
			name = ui.nameLabel.Position,
			weight = ui.weightChip.Position,
			price = ui.priceChip.Position,
			priceSize = ui.priceChip.Size,
		}
		local quint, quad, out = Enum.EasingStyle.Quint, Enum.EasingStyle.Quad, Enum.EasingDirection.Out

		-- Сразу конечное значение (пропуск): твин нулевой длины отменяет идущий.
		local function settle(gui: Instance, goals: { [string]: any })
			UiFx.tween(gui, 0, goals)
			for key, value in goals do
				(gui :: any)[key] = value
			end
		end

		-- Всё, что появится по долям, пока спрятано.
		local hidden: { GuiObject } = { ui.banner, ui.weightChip, ui.priceChip, ui.newStamp, ui.pedestal }
		for _, gui in hidden do
			UiFx.scaleOf(gui).Scale = 0
		end
		ui.newStamp.Visible = isNew
		-- (UI v5: подписи фишек — правее их значков; у карточки сбоку от рыбака наклейка и в
		-- покое, и в шлепке — внутри карточки ниже баннера: CatchFx.fitChip / fitStamp)
		for _, chip in { ui.weightChip, ui.priceChip } do
			local _, chipSize = cardRect(chip)
			CatchFx.fitChip(chip, chipSize)
		end
		local slapFrom: number? = nil
		if isNew and box.dock then
			local stampPos, stampSize = cardRect(ui.newStamp)
			local bannerPos, bannerSize = cardRect(ui.banner)
			slapFrom = CatchFx.fitStamp(ui.newStamp, stampPos, stampSize, {
				x0 = box.center.X - box.size.X / 2,
				y0 = bannerPos.Y + bannerSize.Y,
				x1 = box.center.X + box.size.X / 2,
				y1 = box.center.Y + box.size.Y / 2,
			})
		end
		if mutationStyle then
			UiFx.scaleOf(ui.mutationLabel).Scale = 0
		end
		ui.tapHint.TextTransparency = 1

		-- Карточка рождается у рыбы над головой и встаёт на место с доворотом (Quint Out), растёт
		-- с лёгким перелётом (1.04: у рыбака — в пределах его запаса). Сбоку от рыбака (v5, D2) —
		-- у своего края со стороны рыбы и растёт к середине своего места: ни на миг не на рыбаке
		-- и трофее (CatchFx.birthPoint). Имя — с ней: въезжает справа на CARD.Slide её ширины.
		CatchFx.birth(
			card,
			CatchFx.birthPoint(from, box.center, box.size, box.dock ~= nil),
			offset(box.center.X, box.center.Y)
		)
		local name = ui.nameLabel
		UiFx.scaleOf(name).Scale = 1
		settle(name, { TextTransparency = 0 })
		local nameOutline = name:FindFirstChild("Outline")
		if nameOutline then
			settle(nameOutline, { Transparency = 0 })
		end
		name.Position = rest.name + UDim2.fromOffset(math.round(box.size.X * CARD.Slide), 0)
		UiFx.tween(name, 0.35, { Position = rest.name }, quint, out)
		UiFx.sound("pop", 0.5, 0.9)
		-- Подиум выскакивает под рыбу («удар» 0.5 → 1.12 → 1), его ободок вспыхивает.
		UiFx.punch(ui.pedestal, { from = 0.5, peak = 1.12, delay = 0.2 })
		UiFx.rimFlash(ui.pedestal, { delay = 0.3, bump = 1 })

		-- Затемнение (у обычной — нет) и лучи растут вместе с карточкой.
		local dim = ui.dim
		if reveal.Dim < 1 and dim.Visible and ui.titleSlam.Visible then
			-- Сцена слова уже чуть затемнила весь экран: темнее, а «дырка» под карточкой открывается,
			-- когда карточка почти выросла (Quint Out: 98 % за 0.2 с) и закрыла её собой.
			placeDim(nil)
			dimTo(reveal.Dim, DIM_TIME)
			later(cardTrove, 0.2, function()
				placeDim(box.center, box.size, box.wide, box.dock, box.edge)
			end)
		elseif reveal.Dim < 1 then
			dim.Visible = true
			for _, band in ui.dimBands do
				band.BackgroundTransparency = 1
			end
			-- Чуть позже карточки: пока она летит на место, «дырка» под ней не видна.
			dimTo(reveal.Dim, DIM_TIME, 0.1)
		else
			dim.Visible = false
		end
		-- Лучи растут с карточкой. У слова редкости спицы уже крутятся вокруг рыбы с приземления:
		-- они уходят копией в середину карточки (CatchFx.ghostRays), а за ней вырастают её
		-- собственные — крупные, у карточки сбоку от рыбака обрезанные у его края (UI v5).
		local started = cardRays
		if started and started.serial == catchSerial then
			CatchFx.ghostRays(ui.rays, ui.fishing, box.center, cardTrove)
		end
		local current = startRays(
			fish,
			nil,
			reveal,
			if fanfare then { Palette.Gold.Top, style.Rays[1], Palette.Leaf.Top, style.Rays[2] } else nil
		)
		local rays, extra = current.main, current.extra

		-- Рыба: маленькие лучи цветов редкости за ней (на лице карточки — экран не заливают),
		-- мягкий пульс до последней доли, редкие звёздочки вокруг.
		local stopGlow = cardTrove:Add(UiFx.pulse(ui.fishGlow, 1.08, 1.4))
		cardTrove:Add(UiFx.rays(ui.fishGlow, {
			colors = if style.Rainbow then UIConfig.Rainbow else { style.Top, style.Bottom },
			count = reveal.Glow,
			speed = 18,
			size = 1.15,
			width = 0.07,
			transparency = 0.25,
			glow = false,
			halo = false,
			breathe = false,
			grow = 0.5,
		}))
		cardTrove:Add(UiFx.sparkles(ui.fishGlow, { rate = reveal.Sparkles, size = 0.22, area = 0.3 }))

		-- Редкость на самой карточке (эпическая и выше): «живая» обводка (с мутацией — на баннере:
		-- обводка карточки — её); мифическая: баннер и лицо карточки — бегущая радуга.
		local rimStroke: UIStroke? = nil
		if reveal.Rim > 0 then
			local lip = ui.banner:FindFirstChild("Lip")
			local bannerStroke = lip and lip:FindFirstChildOfClass("UIStroke")
			if not mutationStyle then
				rimStroke = ui.cardOutline
				rarityRim(ui.cardOutline, style, reveal.Rim)
			elseif bannerStroke then
				rimStroke = bannerStroke
				rarityRim(bannerStroke, style, math.min(reveal.Rim, 1.8))
			end
		end
		if style.Rainbow then
			cardTrove:Add(UiFx.rainbow(ui.bannerFill, { speed = 0.45 }))
			local faceFill = UiFx.faceOf(card):FindFirstChild("Fill")
			if faceFill and faceFill:IsA("UIGradient") then
				local pastel: { Color3 } = {}
				for _, color in UIConfig.Rainbow do
					table.insert(pastel, UiFx.lighten(color, 0.8))
				end
				local stopFace = UiFx.rainbow(faceFill, { colors = pastel, speed = 0.12 })
				faceFill.Rotation = 35
				cardTrove:Add(function()
					stopFace()
					faceFill.Rotation = 90
				end)
			end
		end

		-- Расписание долей (c+…): каждая — не ближе beat к предыдущей (имя уже родилось с карточкой).
		local beat = reveal.Beat
		local titleUp = ui.titleSlam.Visible
		local bannerAt = if titleUp then CARD.Morph - 0.06 else CARD.Banner
		local newAt = bannerAt + beat
		local chipsAt = (if isNew then newAt else bannerAt) + beat
		local countStart = chipsAt + CARD.Count
		local landed = countStart + reveal.Count

		-- Редкость: огромное слово (эпическая и выше, «висит» с приземления) с первым же тактом
		-- карточки летит в баннер, и баннер вырастает из него; без слова в c+CARD.Banner баннер
		-- «раскатывается» из середины (ширина растёт, Quint Out).
		local bannerShown = false
		local function showBanner(instant: boolean)
			if bannerShown then
				return
			end
			bannerShown = true
			local banner = ui.banner
			local label = ui.rarityLabel
			local outline = label:FindFirstChild("Outline")
			UiFx.scaleOf(banner).Scale = 1
			if instant then
				UiFx.scaleOf(child(banner, "StarLeft")).Scale = 1
				UiFx.scaleOf(child(banner, "StarRight")).Scale = 1
				settle(banner, { Size = rest.banner })
				settle(label, { TextTransparency = 0 })
				if outline then
					settle(outline, { Transparency = 0 })
				end
				return
			end
			if titleUp then
				-- Надпись баннера проявляется, пока слово тает (за 0.08 с): двух слов сразу не видно.
				label.TextTransparency = 1
				UiFx.tween(label, 0.1, { TextTransparency = 0 }, nil, nil, 0.04)
				if outline and outline:IsA("UIStroke") then
					outline.Transparency = 1
					UiFx.tween(outline, 0.1, { Transparency = 0 }, nil, nil, 0.04)
				end
			end
			local width = rest.banner.X.Scale * (if titleUp then 0.55 else 0.2)
			banner.Size = UDim2.new(width, rest.banner.X.Offset, rest.banner.Y.Scale, rest.banner.Y.Offset)
			UiFx.tween(banner, CARD.Grow, { Size = rest.banner }, quint, out)
			UiFx.rimFlash(banner, { delay = CARD.Grow * 0.45 }) -- ободок вспыхивает
			later(cardTrove, CARD.Grow * 0.6, function()
				UiFx.glowRing(banner, { color = style.Top, scale = 1.3, thickness = 3, time = 0.4 })
				UiFx.flashText(label, Palette.Gold.Top) -- слово редкости вспыхивает золотом
			end)
			-- Звёзды по краям выскакивают по очереди и качаются.
			CatchFx.popStars(banner, CARD.Grow * 0.5, cardTrove)
			if style.Rainbow then
				cardTrove:Add(UiFx.sparkles(banner, { rate = 3, size = 0.7, area = 0.1, outside = true }))
			end
		end
		table.insert(skipHooks, function()
			if not bannerShown then
				clearTitle() -- слово ещё летит в баннер: сразу баннер
				showBanner(true)
			end
		end)
		addBeat(if titleUp then 0 else CARD.Banner, function(instant: boolean)
			if instant then
				clearTitle()
				showBanner(true)
				return
			end
			cardTrove:Add(UiFx.arpeggio(fish.Rarity, 0.4))
			if ui.titleSlam.Visible then
				morphTitle(CARD.Morph, function()
					showBanner(false)
				end)
			else
				showBanner(false)
			end
		end)

		-- «НОВИНКА!» — штамп; у нового вида обычной и редкой — ещё искры, горсть конфетти из штампа
		-- и «дзынь» (CARD.New).
		if isNew then
			addBeat(newAt, function(instant: boolean)
				if instant then
					UiFx.scaleOf(ui.newStamp).Scale = 1
					return
				end
				-- «НОВИНКА!» шлёпается наклейкой (CatchFx.slap: крупной с доворотом, вздрагивает,
				-- кольцо и искры).
				local root = ui.fishing.AbsoluteSize
				local pos, size = cardRect(ui.newStamp)
				local center = pos + size / 2
				local at = Vector2.new(center.X / math.max(root.X, 1), center.Y / math.max(root.Y, 1))
				cardTrove:Add(CatchFx.slap(ui.newStamp, ui.fishing, at, cardTrove, slapFrom))
				UiFx.sound("pop", 0.4, 1.3)
				if fanfare then
					local spec = CARD.New
					cardTrove:Add(UiFx.burst(ui.fishing, {
						origin = at,
						count = spec.Sparks,
						colors = { WHITE, Palette.Leaf.Top, Palette.Gold.Top },
						power = 1,
						z = 13,
					}))
					celebrationTrove:Add(UiFx.confettiPop(ui.fishing, {
						count = spec.Confetti,
						colors = spec.Colors,
						origin = at,
						spread = 140,
						power = 0.8,
						duration = 1.3,
					}))
					UiFx.sound("ping", 0.35, 1.6)
				end
			end)
		end
		-- Вес и цена поднимаются (Quad Out), цена — на CARD.Chips позже.
		addBeat(chipsAt, function(instant: boolean)
			local chips: { GuiObject } = { ui.weightChip, ui.priceChip }
			local homes = { rest.weight, rest.price }
			if instant then
				for index, chip in chips do
					settle(UiFx.scaleOf(chip), { Scale = 1 })
					settle(chip, { Position = homes[index] })
				end
				return
			end
			-- По очереди, каждая с «ударом» (0.85 → 1.1 → 1) из-под своего места, «тик» всё выше.
			CatchFx.punchChips(chips, homes, box.size.Y * CARD.Rise, CARD.Chips, cardTrove)
			UiFx.rimFlash(ui.priceChip, { delay = CARD.Chips + 0.12, bump = 1 })
		end)

		-- Цена набегает (с мутацией — сначала до цены без неё).
		local value = math.round(fish.Value)
		local multiplier = if mutated and mutation then math.max(mutation.Multiplier, 1) else 1
		local base = math.round(value / multiplier)
		addBeat(countStart, function(instant: boolean)
			if instant then
				ui.priceLabel.Text = CatchFx.money(base)
				return
			end
			local count = countPrice(0, base, reveal.Count, 1, 1.4)
			stopPriceCount = count
			cardTrove:Add(count)
		end)

		--[[
			«+$4/с» — то самое «число растёт» — вылетает из фишки цены (она подпрыгивает: источник) на
			свободное место и не закрывает ни цену, ни «×N» (CARD.PriceFloat): справа от карточки на
			высоте чуть выше цены (или в 2 и 3.5 раза выше — где просторнее: мешают только кнопки на
			этой высоте); тесно — надпись меньше (не меньше MinTitle × Title), совсем тесно — быстро
			вверх, над строкой веса (на имя). Back Out за Fly, потом поднимается и тает.
		]]
		local function floatPrice(_amount: number, share: number)
			local spec = CARD.PriceFloat
			local root = ui.fishing.AbsoluteSize
			-- Этап 3: доход рыбы «+$4/с» (зелёный) или, если её сразу продали, золотое «+$15».
			local text, floatColors = CatchFx.priceFloat(fish.Income, cardTank)
			local perHeight = (utf8.len(text) or 6) * 0.6 -- ширина надписи в её высотах
			local chipPos, chipSize = cardRect(ui.priceChip)
			-- Вылетает из верхнего края фишки (чуть правее середины): само число не закрывает.
			local source = chipPos + Vector2.new(chipSize.X * 0.62, chipSize.Y * 0.1)
			local edge = box.center.X + box.size.X * (if box.wide then CARD.Span else CARD.SquareSpan) / 2 + spec.Gap
			local height, spot = root.Y * share, nil
			for _, lift in { spec.Lift, spec.Lift * 2, spec.Lift * 3.5 } do
				local y = math.max(source.Y - root.Y * lift, root.Y * share / 2 + 4)
				local _, right = sideLimits(root, y - root.Y * share / 2, y + root.Y * share / 2, true)
				local fit = math.min(root.Y * share, (right - edge) / perHeight)
				if not spot or fit > height then
					height, spot = fit, Vector2.new(edge + fit * perHeight / 2, y)
				end
			end
			local life = spec.Time
			if box.dock and box.edge then
				-- Карточка сбоку от рыбака (v3): по сторонам — он сам и край экрана. UI v5 (SIMC-C1-03):
				-- «+$4/с» — не на окно с рыбой (на неё как раз смотрят), а над баннером или у внешнего
				-- края карточки (CatchFx.floatSpot); нет места и там — на верх окна, и тает раньше.
				local windowPos, windowSize = cardRect(ui.window)
				local half = box.size * Vector2.new(if box.wide then CARD.Span else CARD.SquareSpan, 1) / 2
				local early = false
				-- (наклейка «НОВИНКА!» — как нарисована сейчас: с обводкой и наклоном, ≈ +4 px)
				local sticker = nil
				if ui.newStamp.Visible then
					local at = ui.newStamp.AbsolutePosition - ui.fishing.AbsolutePosition
					local reach = ui.newStamp.AbsoluteSize
					local pad = CatchFx.outline(ui.newStamp) + 4
					sticker = { x0 = at.X - pad, y0 = at.Y - pad, x1 = at.X + reach.X + pad, y1 = at.Y + reach.Y + pad }
				end
				spot, height, early = CatchFx.floatSpot({
					root = root,
					card = {
						x0 = box.center.X - half.X,
						y0 = box.center.Y - half.Y,
						x1 = box.center.X + half.X,
						y1 = box.center.Y + half.Y,
					},
					side = box.dock,
					edge = box.edge,
					window = {
						x0 = windowPos.X,
						y0 = windowPos.Y,
						x1 = windowPos.X + windowSize.X,
						y1 = windowPos.Y + windowSize.Y,
					},
					source = source,
					perHeight = perHeight,
					want = root.Y * share,
					least = math.min(root.Y * share, UiFx.textSize("Title") * spec.MinTitle),
					gap = spec.Gap,
					-- (у верха HUD — правее кнопок меню и чата Roblox, на любом экране, SIMC-C2-03; без
					-- тач-экрана — и не на окне чата и списке игроков Roblox)
					limits = function(top: number, bottom: number): (number, number)
						local left, right = sideLimits(root, top, bottom, true)
						if top < Layout.EDGE then
							left = math.max(left, CLIMAX.TopbarRight)
						end
						if not UserInputService.TouchEnabled then
							left = if top < CLIMAX.ChatBottom then math.max(left, CLIMAX.ChatRight) else left
							right = if top < CLIMAX.ListBottom then math.min(right, root.X - CLIMAX.ListLeft) else right
						end
						return left, right
					end,
					rise = root.Y * spec.Rise,
					sticker = sticker,
				})
				if early then
					life = spec.Early
				end
				if not spot then
					return -- (места нет нигде: фишка и так пружинит и сыплет искры)
				end
			elseif height < math.min(root.Y * share, UiFx.textSize("Title") * spec.MinTitle) then
				-- Справа места нет: вверх, над строкой веса (её верх — над фишкой цены).
				height = root.Y * share
				local weightPos = cardRect(ui.weightChip)
				local half = height * perHeight / 2
				spot = Vector2.new(
					math.clamp(source.X, half + 8, math.max(half + 8, root.X - half - 8)),
					math.max(weightPos.Y - height * 0.55, height / 2 + 4)
				)
			end
			local at = spot :: Vector2
			local w, h = math.max(root.X, 1), math.max(root.Y, 1)
			local label = UiFx.floatText(ui.fishing, text, {
				position = UDim2.fromScale(source.X / w, source.Y / h),
				to = UDim2.fromScale(at.X / w, at.Y / h),
				travel = spec.Fly,
				size = UDim2.fromScale(height * perHeight / w, height / h),
				colors = floatColors,
				rise = spec.Rise,
				time = life,
				rotate = -5,
				z = 30,
			})
			label.Name = "FxPriceFloat"
			local outline = label:FindFirstChild("Outline")
			if outline and outline:IsA("UIStroke") then
				outline.Thickness = math.max(UIConfig.Fx.TextStrokeMin, math.round(height * 0.06))
			end
			UiFx.bump(ui.priceChip, 1.12, 0.25)
			UiFx.sound("swoosh", 0.25, 1.6)
		end

		-- Цена «приземлилась» по-настоящему (без мутации — сразу, с мутацией — после пересчёта):
		-- фишка сплющивается и пружинит (Elastic Out, центр на месте), блик, искры, «дзынь»,
		-- через CARD.PriceFloat.Delay из неё вылетает «+$4/с»; легендарная и мифическая — дождь 💰
		-- и залп конфетти, мифическая — ещё радужные края экрана и лёгкая тряска.
		local function pricePop(amount: number, sparks: { Color3 })
			local chip = ui.priceChip
			ui.priceLabel.Text = CatchFx.money(amount)
			local w, h = rest.priceSize.X.Scale, rest.priceSize.Y.Scale
			local anchor = chip.AnchorPoint
			chip.Size = UDim2.new(w * 1.25, rest.priceSize.X.Offset, h * 0.85, rest.priceSize.Y.Offset)
			chip.Position = rest.price
				+ UDim2.fromScale((0.5 - anchor.X) * w * (1 - 1.25), (0.5 - anchor.Y) * h * (1 - 0.85))
			UiFx.tween(
				chip,
				0.45,
				{ Size = rest.priceSize, Position = rest.price },
				Enum.EasingStyle.Elastic,
				Enum.EasingDirection.Out
			)
			UiFx.wiggle(ui.priceIcon, 18, 3, 0.45)
			UiFx.flashText(ui.priceLabel, Palette.Gold.Top) -- цифры вспыхивают золотом
			UiFx.shine(chip, 0.5)
			UiFx.sound("pop", 0.45, 1.5)
			UiFx.sound("ping", 0.3, 2)
			local root = ui.fishing.AbsoluteSize
			local pos, size = cardRect(chip)
			local center = pos + size / 2
			cardTrove:Add(UiFx.burst(ui.fishing, {
				origin = Vector2.new(center.X / math.max(root.X, 1), center.Y / math.max(root.Y, 1)),
				count = if reveal.Float > 0 then 14 else 10,
				colors = if style.Rainbow then UIConfig.Rainbow else sparks,
				power = 0.9,
				z = 13,
			}))
			-- «+$4/с»: когда фишка «села» — вылетает из неё на свободное место (floatPrice).
			-- (Этап 3: рыба, проданная сразу, — всегда золотое «+$15»: её деньги)
			local share = if reveal.Float > 0
				then reveal.Float
				elseif mutated or CatchFx.isSold(cardTank) then CARD.New.Float
				else 0
			if share > 0 then
				later(cardTrove, CARD.PriceFloat.Delay, function()
					floatPrice(amount, share)
				end)
			end
			if reveal.Coins > 0 then
				coinRain(reveal.Coins, 1.5)
			end
			if reveal.Confetti2 > 0 then
				celebrationTrove:Add(UiFx.confetti(ui.hud, {
					count = reveal.Confetti2,
					colors = style.Confetti,
					origin = Vector2.new(0.5, 0.25),
					spread = 160,
					power = 0.9,
				}))
			end
			if style.Rainbow then
				-- Мифическая: радужная обводка на миг вспыхивает толще, от цены — радужное кольцо,
				-- лёгкая тряска (без заливки экрана: на телефоне её бюджет уже у карточки).
				-- (Твин толщины уходит вместе с карточкой: иначе он дописал бы толстую обводку
				-- уже после того, как rim вернул её.)
				local stroke = rimStroke
				if stroke then
					local thickness = stroke.Thickness
					stroke.Thickness = thickness * 1.35
					local flare = UiFx.tween(stroke, 0.4, { Thickness = thickness }, quad, out)
					cardTrove:Add(function()
						flare:Cancel()
					end)
				end
				UiFx.glowRing(chip, { color = WHITE, scale = 1.5, thickness = 5, time = 0.45 })
				UiFx.cameraShake(0.2, 0.3)
			end
		end

		-- Цена без мутации «приземлилась» — праздник; с мутацией — только «тик» (праздник будет у
		-- полной цены после пересчёта).
		addBeat(landed, function(instant: boolean)
			local count = stopPriceCount
			stopPriceCount = nil
			if count then
				count()
			end
			ui.priceLabel.Text = CatchFx.money(base)
			if instant then
				return
			end
			if mutated then
				UiFx.bump(ui.priceChip, 1.15, 0.25)
				UiFx.sound("tick", 0.4, 1.5)
			else
				pricePop(base, { WHITE, Palette.Gold.Top, Palette.Sun.Top })
			end
		end)

		-- Мутация (цена сперва «дышит» одну долю): штамп на углу рыбы, «×N» у цены, цена
		-- пересчитывается до полной и «приземляется» с праздником, обводка карточки в её цветах.
		local finish = landed
		if mutationStyle and mutation then
			local stampAt = landed + beat
			finish = stampAt + 0.67
			addBeat(stampAt, function(instant: boolean)
				mutationRim(mutationStyle)
				mutationFx(mutationStyle)
				ui.priceMult.Visible = true
				if instant then
					UiFx.scaleOf(ui.mutationLabel).Scale = 1
					UiFx.scaleOf(ui.priceMult).Scale = 1
					ui.priceLabel.Text = CatchFx.money(value)
					return
				end
				stampIn(ui.mutationLabel, 1.8, 12, 0.3)
				UiFx.sound("swoosh", 0.4, 1.2)
				UiFx.sound("pop", 0.5, 1.1)
				-- Хвосты этой доли (штамп «×N», пересчёт, «приземление»). Тап-пропуск их отменяет:
				-- конечный вид («×N» на месте, полная цена) ставят он и доля finish.
				local steps = cardTrove:Add(Trove.new())
				table.insert(skipHooks, function()
					steps:Clean()
					UiFx.scaleOf(ui.priceMult).Scale = 1
				end)
				later(steps, 0.15, function()
					UiFx.stamp(ui.priceMult, 16, 0.25)
					UiFx.sound("pop", 0.45, 1.4)
				end)
				later(steps, 0.25, function()
					local recount = countPrice(base, value, 0.4, 1.2, 1.8)
					stopPriceCount = recount
					cardTrove:Add(recount)
				end)
				later(steps, 0.65, function()
					local recount = stopPriceCount
					stopPriceCount = nil
					if recount then
						recount()
					end
					pricePop(
						value,
						if mutationStyle.Effect == "rainbow"
							then UIConfig.Rainbow
							else { WHITE, mutationStyle.Top, mutationStyle.Bottom }
					)
				end)
			end)
			addBeat(finish - 0.02, function(_instant: boolean)
				local recount = stopPriceCount
				stopPriceCount = nil
				if recount then
					recount()
				end
				ui.priceLabel.Text = CatchFx.money(value)
			end)
		end

		-- Последняя доля: подсказка «Тапни — забрать!», кнопка — «ЗАБРАТЬ!», всё успокаивается
		-- (лучи, свечение, звёзды реже); мифическая «дышит» и покачивается.
		local last = finish + beat
		if CatchFx.tankStamp(cardTank) then
			-- Этап 3: штамп садка шлёпается своей долей, когда цена встала (CatchFx.showTankStamp).
			local stampAt = last
			last += beat
			addBeat(stampAt, function(instant: boolean)
				local root = ui.fishing.AbsoluteSize
				local pos, size = cardRect(ui.tankStamp)
				local center = pos + size / 2
				local at = Vector2.new(center.X / math.max(root.X, 1), center.Y / math.max(root.Y, 1))
				CatchFx.showTankStamp(ui.tankStamp, ui.fishing, at, cardTrove, instant)
			end)
		end
		addBeat(last, function(instant: boolean)
			cardSettled = true
			stopGlow()
			rays:settle({ alphaAdd = 0.18, spinMul = 0.5, time = 0.6 })
			if extra then
				extra:settle({ alphaAdd = 0.18, spinMul = 0.5, time = 0.6 })
			end
			-- Подсказка проявляется, потом мягко «дышит» 0 ↔ 0.15 (период 1.2 с: читается всегда).
			local hint = ui.tapHint
			hint.TextTransparency = if instant then 0 else 1
			local appear = UiFx.tween(hint, 0.25, { TextTransparency = 0 })
			local breathe = TweenService:Create(
				hint,
				TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ TextTransparency = 0.15 }
			)
			later(cardTrove, 0.3, function()
				hint.TextTransparency = 0
				breathe:Play()
			end)
			cardTrove:Add(function()
				appear:Cancel()
				breathe:Cancel()
				hint.TextTransparency = 0
			end)
			-- Кнопка действия просыпается: «ЗАБРАТЬ!» (как и подсказка — закрыть). Сначала гашение
			-- снимается мгновенно, потом вид (его «выскок» прячет смену): твин «разгашения» перебил
			-- бы ореол «ЗАБРАТЬ!».
			unfadeGroup(ui.actionButton, 0)
			refreshButtons()
			if style.Flash then
				-- Блик по баннеру — когда «+$4/с» уже растаял (заливка на телефоне).
				cardTrove:Add(UiFx.shineLoop(ui.banner, { interval = 2.4, delay = if instant then 0.4 else 0.9 }))
			end
			if style.Rainbow then
				glitter(8)
				-- (После толчка пропуска — не спорить с ним за масштаб.)
				-- Растёт вверх: низ стоит (до хотбара всё те же 16 px), верх поднимается.
				later(cardTrove, if instant then 0.3 else 0, function()
					cardTrove:Add(UiFx.pulse(card, CARD.Breath, CARD.BreathPeriod))
					local home = offset(box.center.X, box.center.Y)
					local rise = math.round(box.size.Y * (CARD.Breath - 1) / 2)
					card.Position = home
					local bob = TweenService:Create(
						card,
						TweenInfo.new(
							CARD.BreathPeriod / 2,
							Enum.EasingStyle.Sine,
							Enum.EasingDirection.InOut,
							-1,
							true
						),
						{ Position = home - UDim2.fromOffset(0, rise) }
					)
					bob:Play()
					cardTrove:Add(function()
						bob:Cancel()
						card.Position = home
					end)
				end)
			end
		end)

		-- Сама закроется: по редкости (UIConfig.CatchCardTime), но не раньше, чем через CARD.Linger
		-- после последней доли; рыба продана сразу — не раньше CatchFx.SOLD_HOLD после доли штампа
		-- (last − beat): «САДОК ПОЛОН / ПРОДАНА» успевают прочесть (CatchFx.cardTime).
		local auto = CatchFx.cardTime(
			math.max(UIConfig.CatchCardTime[fish.Rarity] or UIConfig.CatchCardTime.Common, last + CARD.Linger),
			last - beat,
			cardTank
		)
		later(cardTrove, auto, closeCard)
		cardTrove:Add(function()
			local count = stopPriceCount
			stopPriceCount = nil
			if count then
				count()
			end
		end)

		refreshContextHint()
	end

	-- Рыба приземлилась над головой (или прыжка нет): удар в точке рыбы (кольца, искры; у
	-- легендарной и мифической — ещё лёгкий отсвет экрана, у мифической — радужные края), тряска,
	-- «толчок», конфетти из точки над головой; у эпической и выше — лучи и огромное слово (сцена
	-- слова); через Hold — карточка. На весь экран ничего яркого: приземление должно быть видно.
	local function onLanded(fish: FishingRules.FishData, serial: number, world: Vector3?)
		if serial ~= catchSerial then
			return
		end
		local style = UIConfig.Rarity[fish.Rarity] or UIConfig.Rarity.Common
		local reveal = REVEAL[fish.Rarity] or REVEAL.Common
		local point = screenPoint(world or headPoint())
		local rootSize = ui.fishing.AbsoluteSize
		local origin = if point
			then Vector2.new(point.X / math.max(rootSize.X, 1), point.Y / math.max(rootSize.Y, 1))
			else Vector2.new(0.45, 0.32)

		-- Удар — тонкое кольцо вокруг рыбы (CLIMAX.Shock), без свечения в середине и без вспышки
		-- краёв экрана: чёткий удар в точке рыбы, а не заливка кадра (v3; белый шар и «звезда»
		-- тонких лучей — в мире, FishingFxController).
		local shock = CLIMAX.Shock
		-- (кольца начинаются снаружи трофея — CatchFx.clearRadius: огромная рыба на маленьком
		-- телефоне шире 0.3 высоты экрана, и кольцо иначе проходило бы по ней)
		local clear =
			CatchFx.clearRadius(fishBox(fish), point or Vector2.new(origin.X * rootSize.X, origin.Y * rootSize.Y))
		UiFx.shockwave(ui.hud, origin, {
			color = style.Top,
			colors = if style.Rainbow then UIConfig.Rainbow else nil,
			size = shock.Size + shock.Grow * reveal.Burst,
			thickness = shock.Thickness,
			time = shock.Time,
			glow = 1,
			from = if clear then 2 * clear / math.max(rootSize.Y, 1) else nil,
		})
		-- Искры — следом за кольцом (в кадр приземления рыбу ничто не закрывает).
		later(celebrationTrove, 0.05, function()
			celebrationTrove:Add(UiFx.burst(ui.hud, {
				origin = origin,
				count = math.round(8 + 6 * reveal.Burst),
				colors = { WHITE, style.Top, Palette.Gold.Top },
				power = 0.8 + reveal.Burst * 0.6,
				size = 1.6,
				z = 61,
			}))
		end)
		if reveal.Shake then
			UiFx.cameraShake(0.35, 0.4)
		end
		if reveal.Fov ~= 0 then
			UiFx.fovPunch(reveal.Fov)
		end
		if reveal.Confetti > 0 then
			-- Чуть после удара: в кадр приземления рыбу ничто не закрывает.
			later(celebrationTrove, 0.1, function()
				celebrationTrove:Add(UiFx.confetti(ui.hud, {
					count = reveal.Confetti,
					colors = style.Confetti,
					origin = origin,
					spread = 150,
					power = 1.05,
				}))
			end)
			if reveal.ConfettiMid > 0 then
				-- Мифическая: второй залп — когда первый уже редеет (общий лимит конфетти).
				later(celebrationTrove, CARD.ConfettiMid, function()
					celebrationTrove:Add(UiFx.confetti(ui.hud, {
						count = reveal.ConfettiMid,
						colors = style.Confetti,
						origin = Vector2.new(0.5, 0.2),
						spread = 170,
						power = 0.9,
					}))
				end)
			end
		end
		UiFx.sound("pop", 0.5, if reveal.Flash then 0.8 else 1)
		if reveal.Flash then
			UiFx.sound("swoosh", 0.5, 0.7)
		end
		if reveal.Title then
			-- Сцена слова (через CLIMAX.TitleDelay — в кадр приземления видна сама рыба): лучи бьют
			-- из рыбы над головой (середина пустая — рыбу видно), огромное слово — ниже неё, на
			-- лучах; карточка — когда оно сложилось и постояло (Hold): лучи переезжают за ней, слово
			-- летит в её баннер.
			local trophy = fishBox(fish)
			placeCard(reveal.Scale, trophy, CARD.DockSlack, reveal)
			local at = point or Vector2.new(origin.X * rootSize.X, origin.Y * rootSize.Y)
			later(catchTrove, CLIMAX.TitleDelay, function()
				startRays(fish, CLIMAX.RaysHole, nil, nil, CatchFx.clearRadius(trophy, at), at)
				slamTitle(fish.Rarity, reveal, style, trophy)
			end)
			-- Слово вылетает к месту баннера за CLIMAX.Lead до карточки: она рождается под уже
			-- улетевшим словом (не «наезжает» на него посреди экрана); баннер вырастает из него.
			later(catchTrove, math.max(reveal.Hold - CLIMAX.Lead, CLIMAX.TitleDelay), function()
				if ui.titleSlam.Visible and not ui.card.Visible then
					aimTitle(CLIMAX.Aim)
				end
			end)
			-- Экран чуть темнеет целиком (CLIMAX.TitleDim): лучи и буквы ярче; карточка (если она
			-- уже не открылась) потом темнит до своего.
			later(catchTrove, CLIMAX.TitleDim.At, function()
				if reveal.Dim >= 1 or ui.card.Visible or (cardBox and cardBox.dock) then
					return -- (v3: карточка сбоку от рыбака — он с трофеем остаётся ярким)
				end
				local dim = ui.dim
				placeDim(nil)
				dim.Visible = true
				for _, band in ui.dimBands do
					band.BackgroundTransparency = 1
				end
				dimTo(reveal.Dim + CLIMAX.TitleDim.Add, 0.2)
				catchTrove:Add(function()
					if not ui.card.Visible then
						dim.Visible = false
					end
				end)
			end)
		end
		later(catchTrove, reveal.Hold, function()
			openCard(fish, point)
		end)
	end

	-- Начало улова (сразу после "Caught"): кнопка замирает, счётчик держит число, напряжение
	-- нарастает, ждём приземления рыбы.
	function beginCatch(fish: FishingRules.FishData, total: number)
		catchTrove:Clean()
		celebrationTrove:Clean()
		if ui.card.Visible then
			closeCard() -- прошлая карточка ещё открыта (редко): уходит сразу
		end
		catchSerial += 1
		local serial = catchSerial
		catchScreen = true
		holdCounter(serial, total)
		refreshButtons()
		fadeGroup(ui.actionButton, BUTTON_FADE, 0.2)
		-- Плашки статуса гаснут сразу: рыба летит над ними (а дальше на их месте — карточка).
		fadeGroup(ui.status, 1, STATUS_FADE)
		refreshContextHint()

		local style = UIConfig.Rarity[fish.Rarity] or UIConfig.Rarity.Common
		local reveal = REVEAL[fish.Rarity] or REVEAL.Common
		local leap = FishingConfig.LeapTime -- прыжок начался вместе с "Caught" (FishFx пришёл раньше)
		if reveal.Tension then
			-- Узкая рамка нарастает к приземлению и обрывается на нём (catchTrove чистится в кадр
			-- удара): удар — разрядка, а не самый закрашенный кадр. Мифическая — светлая радуга по
			-- кругу (не сиреневая пелена поверх радужной рыбы).
			local tension = CLIMAX.Tension
			local cycle: { Color3 }? = nil
			if style.Rainbow then
				local light = {}
				for _, color in UIConfig.Rainbow do
					table.insert(light, UiFx.lighten(color, tension.Light))
				end
				cycle = light
			end
			later(catchTrove, 0.3, function()
				local stop = UiFx.edgeVignette(ui.hud, { style.Bottom, style.Top }, tension.To, nil, {
					from = tension.From,
					fadeIn = math.max(leap - 0.3, 0.1),
					build = true,
					size = tension.Size,
					cycle = cycle,
				})
				catchTrove:Add(function()
					stop(0)
				end)
			end)
		end
		if reveal.Heartbeat then
			-- «Сердце» бьётся всё чаще (звук; рамка нарастает сама).
			for index, at in CLIMAX.Heartbeat do
				later(catchTrove, at * leap, function()
					UiFx.sound("splash", 0.4 + 0.03 * index, 0.5 + 0.025 * index)
				end)
			end
		end
		if reveal.Fov ~= 0 then
			-- Камера чуть «отъезжает» перед приземлением — тем сильнее потом «толчок».
			later(catchTrove, math.max(leap - 0.25, 0), function()
				UiFx.fovPunch(-reveal.Fov * 0.3, 0.25, 0.12, true)
			end)
		end

		-- Приземление: сигнал FishingFxController (или он уже был — прыжка нет), иначе — сами.
		local done = false
		local function landed(world: Vector3?)
			if done then
				return
			end
			done = true
			landingWaiter = nil
			catchTrove:Clean() -- виньетка и «сердце» кончаются, ожидание тоже
			onLanded(fish, serial, world)
		end
		local early = lastLanding
		lastLanding = nil
		if early and os.clock() - early.at <= LANDING_MEMORY then
			landed(early.position)
		else
			landingWaiter = landed
			later(catchTrove, CATCH_FALLBACK, function()
				landed(nil)
			end)
		end
		-- Подстраховка: что бы ни случилось, кнопка и счётчик не останутся «замороженными».
		task.delay(CATCH_FAILSAFE, function()
			if serial == catchSerial and catchScreen and not ui.card.Visible then
				finishCatch(serial, false)
			end
		end)
	end

	-- FishingFxController.OwnFishLanded: своя рыба долетела (может прийти раньше "Caught").
	function onOwnFishLanded(_rarity: string, position: Vector3)
		local waiter = landingWaiter
		if waiter then
			waiter(position)
		else
			lastLanding = { at = os.clock(), position = position }
		end
	end

	-- FishData из данных сервера (только нужные поля, с проверкой типов).
	function parseFish(value: any): FishingRules.FishData?
		if typeof(value) ~= "table" or typeof(value.Id) ~= "string" then
			return nil
		end
		local def = FishingRules.GetFish(value.Id)
		local rarity = if typeof(value.Rarity) == "string" then value.Rarity elseif def then def.Rarity else "Common"
		return {
			Id = value.Id,
			Rarity = rarity,
			Mutation = if typeof(value.Mutation) == "string" then value.Mutation else nil,
			Kg = number(value.Kg, 0),
			Value = number(value.Value, 0),
			Income = number(value.Income, 0),
			Uid = if typeof(value.Uid) == "string" then value.Uid else nil,
			New = if typeof(value.New) == "boolean" then value.New else nil,
		}
	end
end

--------------------------------------------------------------------------------
-- Поклёвка и мини-игра
--------------------------------------------------------------------------------

-- Наружу из раздела (блок do … end, см. «Устройство файла» в шапке):
local holdWin -- победное нажатие (tap): стрелка замирает, зона золотая, ждём "Caught"
local predictedHit: number? = nil -- номер попадания, уже отыгранного по предсказанию (до "Zone")
local enterBite, syncFromAttribute, startPending, refreshPips, showMinigame, punchHit, celebrateHit, missGhost
do
	local PENDING_TIMEOUT = 1.5 -- ответа на заброс нет столько секунд — кнопка снова «Забросить»

	-- Полоска поклёвки и кольцо «ПОДСЕЧЬ!»: зелёная → жёлтая (Gold — настоящий жёлтый, не
	-- персиковый верх Sun на оранжевой плашке) → красная (в мини-игре — своя, без зелёного:
	-- UIConfig.Fishing.TimeBar).
	local TIME_COLORS = { Palette.Leaf.Top, Palette.Gold.Top, Palette.Berry.Bottom }

	-- Слова попаданий (type HitWord — в начале файла).
	local HIT_FIRST: HitWord = { text = "ОТЛИЧНО!", colors = { Palette.Leaf.Top, Palette.Leaf.Bottom } }

	local HIT_NEXT: HitWord = { text = "СУПЕР!", colors = { Palette.Sky.Top, Palette.Sky.Bottom } }
	local HIT_MEGA: HitWord = { text = "МЕГА!", colors = UIConfig.Rainbow, rainbow = true }

	local HIT_PERFECT: HitWord = {
		text = "ИДЕАЛЬНО!",
		colors = { Palette.Gold.Top, Palette.Gold.Top, WHITE, Palette.Gold.Top, Palette.Gold.Top },
	}

	-- Поклёвка в одном такте: плашка и кнопка пульсируют вместе, кольцо от кнопки и край экрана —
	-- на каждый такт, знаки «!» качаются по очереди (каждый — раз в два такта). После
	-- BITE_HURRY окна такт ускоряется (пульс сильнее). Вспышки края экрана не чаще 3 раз в секунду.
	local BITE_BEAT = 0.45
	local BITE_FAST_BEAT = 0.3
	local BITE_HURRY = 0.65
	local BITE_EDGE = 0.2 -- толщина солнечных краёв экрана, доля высоты
	-- Свой поплавок ныряет над плашкой (на столько studs, с брызгами): плашка не закрывает
	-- нырок — становится чуть ниже (не меньше BITE_MIN_SCALE) или отъезжает вбок.
	local BITE_DIVE = 1.8
	local BITE_MIN_SCALE = 0.75
	local CUE_BITES = 2 -- первые столько поклёвок за игру 👇 показывает на кнопку (как в мини-игре)
	local CUE_BOUNCE = 0.07 -- 👇 «нажимает» на столько (доля кнопки, вниз — на её край) …
	local CUE_PERIOD = 0.25 -- … за столько секунд туда (и столько же обратно)

	local bitesShown = 0
	local alertSize: UDim2? = nil -- размер плашки из шаблона (поклёвка может её уменьшить)

	-- 👇 качается — «нажимает» кнопку (новичку с тач-экраном: поклёвка, мини-игра; висит над кругом,
	-- чуть левее середины, и тычет вниз, в его край); до уборки trove.
	local function bounceCue(trove: Trove.Trove)
		local cue = ui.tapCue
		cue.Position = defaults.tapCuePosition
		local bounce = TweenService:Create(
			cue,
			TweenInfo.new(CUE_PERIOD, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Position = defaults.tapCuePosition + UDim2.fromScale(0, CUE_BOUNCE) }
		)
		bounce:Play()
		trove:Add(function()
			bounce:Cancel()
			cue.Position = defaults.tapCuePosition
			cue.Visible = false
		end)
	end

	function enterBite(window: number)
		setPhase("Bite")
		hookSent = false
		clearEventHint() -- колонка внизу — для поклёвки
		layoutColumn()
		local alert = ui.biteAlert
		local restSize = alertSize or alert.Size
		alertSize = restSize
		local position, size, float =
			keepClearOfBobber(alert, defaults.alertPosition, restSize, BITE_DIVE, BITE_MIN_SCALE)
		alert.Position = position
		alert.Size = size
		alert.Visible = true
		phaseTrove:Add(function()
			alert.Position = defaults.alertPosition
			alert.Size = restSize
		end)
		-- Тач-экран: тап по плашке — подсечка. Новичку (первые CUE_BITES поклёвок) 👇 у кнопки — если
		-- на ней нет клавиши (F / R2 и так говорит, что жать).
		ui.biteTapPad.Visible = UserInputService.TouchEnabled
		bitesShown += 1
		if bitesShown <= CUE_BITES and keyHint == "" then
			ui.tapCue.Visible = true
			bounceCue(phaseTrove)
		end
		phaseTrove:Add(function()
			ui.biteTapPad.Visible = false
		end)

		-- «КЛЮЁТ!» выпрыгивает из своего поплавка и с размаху встаёт на место (v3: не «удар» на пол-
		-- экрана поверх рыбака — 0.35 → 1 с перелётом по дуге от поплавка; поплавка не видно —
		-- удар 1.6 → 1 на месте), лёгкая тряска; солнечная вспышка, камера на миг «приближается»,
		-- свист и звон.
		local slam = UiFx.scaleOf(alert)
		if float then
			local box = alert.AbsoluteSize
			alert.Position = offset(float.X, float.Y + box.Y * (alert.AnchorPoint.Y - 0.5))
			slam.Scale = 0.35
			UiFx.tween(alert, 0.3, { Position = position }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		else
			-- (Без полёта: у своего рыбака на телефоне — «выскакивает» из малого на месте, иначе
			-- — удар сверху, крупнее себя, но не больше, чем есть места: slamRoom, V-03 — на
			-- планшете удар 1.6 ложился на «ПОДСЕЧЬ!»; места на удар нет — «выскакивает», как там.)
			local room = if ui.fishing.AbsoluteSize.Y < 500 then 1 else slamRoom(alert, position, size, 1.6)
			slam.Scale = if room >= 1.15 then room else 0.35
		end
		UiFx.tween(slam, 0.38, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		-- (Тряска — когда плашка долетела: тряска запоминает место «в покое».)
		later(phaseTrove, if float then 0.31 else 0.21, function()
			UiFx.shake(alert, 0.006, 0.22)
		end)
		UiFx.rimFlash(alert, { delay = 0.16 }) -- ободок вспыхивает
		-- «КЛЮЁТ!» «ударяет» следом за плашкой, знаки «!» влетают по очереди, разворачиваясь.
		UiFx.punch(ui.biteLabel, { from = 0.6, peak = 1.15, delay = 0.16 })
		for index, glyph in ui.biteIcons do
			UiFx.popIn(
				glyph,
				{ from = 0, time = 0.3, delay = 0.18 + 0.05 * index, rotate = if index == 1 then -25 else 25 }
			)
		end
		UiFx.flash(ui.hud, Palette.Sun.Top, 0.22)
		UiFx.fovPunch(-4, 0.06, 0.25)
		UiFx.sound("swoosh", 0.4, 1.4)
		UiFx.sound("ping", 0.45, 1.8)
		-- Спокойные лучи (не закрывают «!» над головой в мире) и солнечные края экрана в такт.
		phaseTrove:Add(UiFx.rays(alert, {
			colors = { Palette.Sun.Top, WHITE, Palette.Gold.Top },
			count = 12,
			speed = 24,
			size = 1.6,
			transparency = 0.45,
			halo = false,
			breathe = false,
		}))
		-- Края экрана начинают светиться с первым тактом (после удара и вспышки — заливка на
		-- телефоне не складывается).
		local stopVignette: ((number?) -> ())? = nil
		later(phaseTrove, BITE_BEAT, function()
			stopVignette = UiFx.edgeVignette(
				ui.hud,
				{ Palette.Sun.Top, Palette.Sun.Bottom },
				0.55,
				BITE_BEAT,
				{ fadeIn = 0.15, size = BITE_EDGE }
			)
		end)
		phaseTrove:Add(function()
			if stopVignette then
				stopVignette()
			end
		end)

		-- Такт: после удара плашка и кнопка пульсируют вместе; к концу окна — быстрее и сильнее.
		local stopAlertPulse: UiFx.Stop? = nil
		phaseTrove:Add(function()
			if stopAlertPulse then
				stopAlertPulse()
			end
		end)
		local function pulseBoth(period: number, peak: number)
			actionPulseTrove:Clean()
			if stopAlertPulse then
				stopAlertPulse()
			end
			stopAlertPulse = UiFx.pulse(alert, peak, period)
			local most = ui.actionButton:GetAttribute("GrowMax") :: number? -- (16 px до кнопки прыжка — layoutColumn)
			actionPulseTrove:Add(UiFx.pulse(ui.actionButton, math.min(peak + 0.04, most or 2), period))
			actionPulseTrove:Add(whiteRings(BITE_BEAT))
		end
		later(phaseTrove, BITE_BEAT, function()
			if not hookSent then
				pulseBoth(BITE_BEAT, 1.06)
			end
		end)
		later(phaseTrove, math.max(window * BITE_HURRY, BITE_BEAT * 1.5), function()
			if not hookSent then
				pulseBoth(BITE_FAST_BEAT, 1.1)
				-- В спешке плашку ещё и потряхивает — через такт (в списке она не стоит: можно).
				every(phaseTrove, BITE_FAST_BEAT * 2, function()
					if not hookSent then
						UiFx.shake(alert, 0.004, 0.15)
					end
				end, 0)
			end
		end)
		for index, icon in ui.biteIcons do
			every(phaseTrove, BITE_BEAT * 2, function()
				UiFx.wiggle(icon, 16, 2, 0.36)
			end, BITE_BEAT * index)
		end
		-- «КЛЮЁТ!» вспыхивает золотом на каждый такт (UiFx.flashText: не чаще 3 раз в секунду).
		every(phaseTrove, BITE_BEAT, function()
			if not hookSent then
				UiFx.flashText(ui.biteLabel, Palette.Gold.Top, 0.3)
			end
		end, BITE_BEAT)

		-- Полоска времени тает (зелёная → жёлтая → красная), и то же время убывает кольцом по краю
		-- кнопки «ПОДСЕЧЬ!» (UiFx.ringTimer: только твины; подсечка его убирает — doAction). Кольцо —
		-- ВНУТРИ круга, вплотную к его тёмной обводке, поверх лица и под лентой подписи (снаружи места
		-- нет: 16 px до кнопки прыжка, D4); под ним тёмная канавка — видно, сколько уже истекло.
		local timer = ui.biteTimer
		timer.Size = defaults.biteTimerSize
		local stopTimer = UiFx.timerBar(timer, math.max(window, 0.05), TIME_COLORS)
		phaseTrove:Add(function()
			stopTimer()
			timer.Size = defaults.biteTimerSize
			timer.BackgroundColor3 = defaults.biteTimerColor
		end)
		phaseTrove:Add(
			UiFx.ringTimer(
				ui.actionButton,
				math.max(window, 0.05),
				{ colors = TIME_COLORS, pad = 0, thickness = 7, z = ui.actionIcon.ZIndex, track = 0.4 }
			)
		)

		-- Кнопка зовёт с первого кадра: кольцо сразу (пульс — с первого такта).
		actionPulseTrove:Add(whiteRings(BITE_BEAT))
	end

	-- Сервер прислал непонятное — подстраиваемся под атрибут FishingState (его ставит сервер).
	function syncFromAttribute()
		local state = player:GetAttribute("FishingState")
		if state == "Waiting" or state == "Reeling" then
			setPhase("Waiting") -- без данных мини-игры можно только ждать или смотать
		elseif state == "Bite" then
			enterBite(FishingConfig.BiteWindow)
		else
			setPhase("Idle")
		end
	end

	function startPending()
		setPhase("Pending")
		pendingThread = task.delay(PENDING_TIMEOUT, function()
			pendingThread = nil
			if phase == "Pending" then
				syncFromAttribute()
			end
		end)
	end

	-- Мини-игра: предсказанные попадания, 🐟 на зоне, подсказка новичку, обводка редкости.
	local NEEDLE_HOLD = 0.05 -- при попадании стрелка на миг «замирает» (только картинка)
	local CUE_MINIGAMES = 2 -- первые столько мини-игр за игру 👇 показывает на кнопку
	local RIDER_TILT = 12 -- 🐟 покачивается ±градусов …
	local RIDER_SWING = 0.3 -- … раз в столько секунд
	local PIPS_SHARE, PIPS_PAD = 0.3, 0.04 -- рамка кружков попаданий: доля ширины панели, зазор (доля рамки)
	local TIME_BAR_LEFT, PANEL_EDGE = 0.105, 0.955 -- полоска времени начинается тут; кружки кончаются тут
	local RARITY_RANK: { [string]: number } = { Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 5 }
	-- Мифический заголовок — радуга без самых тёмных (синего и фиолетового) цветов: на тёмной
	-- панели они не читаются; бежит «маятником» (UiFx.rainbow bounce: голубой не смешивается с
	-- красным — без серой полосы, ART-01).
	local MYTHIC_TITLE = { table.unpack(UIConfig.Rainbow, 1, 5) }
	local AURA_EDGE = 0.16 -- толщина цветных краёв экрана в мини-игре, доля высоты
	-- Кто на крючке — по редкости (лесенка: чем реже, тем «страшнее»); у легендарной и
	-- мифической наездник крупнее (RIDER_BIG) и светится.
	local RIDER_GLYPHS: { [string]: string } = {
		Common = "🐟",
		Rare = "🐠",
		Epic = "🐡",
		Legendary = "🦈",
		Mythic = "🐉",
	}
	local RIDER_BIG = 1.16 -- легендарный / мифический наездник крупнее (и всё равно под заголовком)
	local SHORT_SCREEN = 500 -- HUD ниже — телефон: мини-игра встаёт слева от рыбака
	-- Планшет / ПК: у рыбака панель становится меньше целиком (под ним — не меньше этой доли;
	-- слева от него — не уже MinSize её UISizeConstraint).
	local MINI_DOCK_MIN = 0.75
	local REEL_DIVE = 0.8 -- поплавок в мини-игре мечется и притапливается на столько studs
	local RARITY_WORD_TIME = 0.9 -- слово редкости над панелью (легендарная, мифическая), с

	local needleHoldUntil = 0
	local needleHoldAt = 0
	local minigamesShown = 0
	local cueOn = false
	local riderWiggle: Tween? = nil
	local riderSize: UDim2? = nil -- размер наездника из шаблона
	local auraEdge = false -- края экрана уже светятся цветом редкости (идеальное — без второй виньетки)
	local rarityWordLabel: TextLabel? = nil -- слово редкости над панелью, пока оно на экране
	local Layout = require(script.Parent:WaitForChild("FishingLayout")) -- слова — не на рыбаке и статусе

	-- Плашки статуса (видимые) и флажок базы над плашкой (он выступает за неё вверх и влево), px
	-- HUD.Fishing: большие слова над панелью на них не заходят (ART-04).
	local function statusBoxes(): { any }
		local origin = ui.fishing.AbsolutePosition
		local boxes = {}
		for _, item in ui.status:GetChildren() do
			if item:IsA("GuiObject") and item.Visible then
				for _, part in { item, item:FindFirstChild("FlagSocket") } do
					if part and part:IsA("GuiObject") and part.Visible then
						local at = part.AbsolutePosition - origin
						table.insert(
							boxes,
							Layout.rect(at.X, at.Y, at.X + part.AbsoluteSize.X, at.Y + part.AbsoluteSize.Y)
						)
					end
				end
			end
		end
		return boxes
	end

	--[[
		Слово над панелью (в долях host: середина x, y, ширина w, высота h; поднимается на rise
		высоты host, наклон tilt°, «раздувается» до peak): не на своём рыбаке — по X в сторону от
		него (ART-03), и не на плашках статуса и флажке базы — поднимается меньше, а тесно и на
		месте — чуть вбок или ниже (FishingLayout.clearOf, ART-04). Возвращает середину и подъём
		(доли host).
	]]
	local function wordSpot(
		host: GuiObject,
		x: number,
		y: number,
		w: number,
		h: number,
		rise: number,
		tilt: number,
		peak: number
	): (number, number, number)
		local size = host.AbsoluteSize
		if size.X < 1 or size.Y < 1 then
			return x, y, rise
		end
		local at = host.AbsolutePosition - ui.fishing.AbsolutePosition
		local half = w * peak / 2 + 8 / size.X -- (и 8 px до рыбака: он шевелится)
		local fisher = fisherRect()
		if fisher then
			local lo, hi = (fisher.x0 - at.X) / size.X, (fisher.x1 - at.X) / size.X
			local top, bottom = (fisher.y0 - at.Y) / size.Y, (fisher.y1 - at.Y) / size.Y
			if top < y + h * peak / 2 and bottom > y - h / 2 - rise and lo < x + half and hi > x - half then
				x = if (lo + hi) / 2 >= x then lo - half else hi + half
			end
		end
		local cx, cy = at.X + x * size.X, at.Y + y * size.Y
		local hw, hh = w * size.X / 2, h * size.Y / 2
		local lift = math.sin(math.rad(math.abs(tilt))) * hw -- (наклон задирает край)
		local dx, dy, up = Layout.clearOf(
			Layout.rect(cx - hw, cy - hh * peak - lift, cx + hw, cy + hh),
			rise * size.Y,
			statusBoxes(),
			8,
			ui.fishing.AbsoluteSize.X
		)
		return x + dx / size.X, y + dy / size.Y, up / size.Y
	end

	function refreshPips(mg: Minigame)
		for index, pip in ui.pips do
			local done = index <= mg.Hits
			pip.Visible = index <= mg.HitsNeeded
			pip.BackgroundColor3 = if done then COLORS.PipDone else defaults.pipColor
			local star = pip:FindFirstChild("Star")
			if star and star:IsA("TextLabel") then
				star.Text = if done then "⭐" else "★"
				star.TextTransparency = if done then 0 else 0.55
			end
		end
		-- Полоска времени тянется до кружков (их 1–5): без пустого места посередине.
		local frame = ui.pipsFrame.AbsoluteSize
		local count = math.clamp(mg.HitsNeeded, 1, #ui.pips)
		local base = defaults.timeBarSize
		if frame.X > 1 then
			local used = PIPS_SHARE * (count * frame.Y / frame.X + (count - 1) * PIPS_PAD)
			local width = math.clamp(PANEL_EDGE - used - 0.035 - TIME_BAR_LEFT, 0.2, base.X.Scale + PIPS_SHARE)
			ui.timeBar.Size = UDim2.new(width, 0, base.Y.Scale, base.Y.Offset)
		else
			ui.timeBar.Size = base
		end
	end

	-- Центр кружка попадания index из count видимых, в долях панели (кружки прижаты вправо).
	local function pipPoint(index: number, count: number): Vector2
		local panel = ui.minigame.AbsoluteSize
		local frame = ui.pipsFrame.AbsoluteSize
		if panel.X < 1 or frame.X < 1 then
			return Vector2.new(PANEL_EDGE, 0.72)
		end
		local pip = frame.Y / panel.X -- кружок (квадрат по высоте рамки) в долях ширины панели
		local pad = PIPS_PAD * frame.X / panel.X
		local fromRight = count - index
		local x = PANEL_EDGE - (fromRight + 0.5) * pip - fromRight * pad
		return Vector2.new(x, 0.72)
	end

	-- Каждый кадр: стрелка по общей формуле, полоска оставшегося времени и 👇 новичку.
	local function updateMinigameFrame()
		local mg = minigame
		if not mg then
			return
		end
		local now = os.clock()
		local elapsed = now - minigameStart
		local u = FishingRules.Needle(mg.U0, mg.Speed, elapsed)
		ui.needle.Position = UDim2.fromScale(if now < needleHoldUntil then needleHoldAt else u, defaults.needleY)
		local spent = math.clamp(elapsed / mg.Timeout, 0, 1)
		ui.timeFill.Size = UDim2.fromScale(1 - spent, 1)
		ui.timeFill.BackgroundColor3 = UiFx.sampleColors(UIConfig.Fishing.TimeBar, spent)
		if cueOn then
			ui.tapCue.Visible = predictedHit == nil and FishingRules.IsHit(u, mg.ZoneCenter, mg.ZoneWidth)
		end
	end

	-- Заголовок: белый сверху, цвет редкости снизу (мифическая — бегущая радуга).
	local function styleTitle(rarityId: string)
		local style = UIConfig.Rarity[rarityId] or UIConfig.Rarity.Common
		local fill = ui.titleFill
		if style.Rainbow then
			fill.Color = UiFx.sequence(MYTHIC_TITLE)
			fill.Rotation = 0
			phaseTrove:Add(UiFx.rainbow(fill, { speed = 0.5, colors = MYTHIC_TITLE, bounce = true }))
		else
			fill.Color = ColorSequence.new(WHITE, style.Top)
			fill.Rotation = 90
		end
	end

	local function startRiderWiggle()
		local rider = ui.rider
		if riderWiggle then
			riderWiggle:Cancel()
		end
		rider.Rotation = -RIDER_TILT
		local wiggle = TweenService:Create(
			rider,
			TweenInfo.new(RIDER_SWING, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Rotation = RIDER_TILT }
		)
		wiggle:Play()
		riderWiggle = wiggle
	end

	local function stopRiderWiggle()
		local wiggle = riderWiggle
		riderWiggle = nil
		if wiggle then
			wiggle:Cancel()
		end
	end

	-- Наездник на зоне (🐟 🐠 🐡 🦈 🐉 — по редкости): стоит на её верхнем крае (над зоной, под
	-- стрелкой, в полосе под заголовком) и покачивается; у легендарной и мифической — крупнее, на
	-- «дышащем» светлом диске цвета редкости (свой фон метки — под глифом: тёмная 🦈 читается на
	-- тёмно-синей панели) с тонкими кольцами в той же полосе — не через буквы заголовка
	-- (SIMB-C2-03).
	local function showRider(mg: Minigame)
		local rider = ui.rider
		local rest = riderSize or rider.Size
		riderSize = rest
		local big = (RARITY_RANK[mg.Rarity] or 1) >= 4
		rider.Text = RIDER_GLYPHS[mg.Rarity] or RIDER_GLYPHS.Common
		rider.Size = if big
			then UDim2.new(rest.X.Scale * RIDER_BIG, rest.X.Offset, rest.Y.Scale * RIDER_BIG, rest.Y.Offset)
			else rest
		rider.Position = UDim2.fromScale(mg.ZoneCenter, defaults.riderY)
		rider.Visible = true
		UiFx.popIn(rider, { from = 0, time = 0.35, delay = 0.15 })
		startRiderWiggle()
		if big then
			local style = UIConfig.Rarity[mg.Rarity] or UIConfig.Rarity.Common
			local glowColor = if style.Rainbow then WHITE else style.Top
			rider.BackgroundColor3 = glowColor
			rider.BackgroundTransparency = 0
			local glow = TweenService:Create(
				rider,
				TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ BackgroundTransparency = 0.2 }
			)
			glow:Play()
			phaseTrove:Add(function()
				glow:Cancel()
			end)
			phaseTrove:Add(UiFx.glowRing(rider, {
				loop = true,
				color = glowColor,
				scale = 1.3,
				thickness = 2,
				time = 0.7,
				interval = 0.8,
			}))
		end
		phaseTrove:Add(function()
			stopRiderWiggle()
			rider.Visible = false
			rider.Rotation = 0
			rider.BackgroundTransparency = 1
			rider.Size = rest
			rider.Position = UDim2.fromScale(0.5, defaults.riderY)
		end)
	end

	-- Зона прыгнула: 🐟 перелетает за ней дугой с кувырком, в конце — всплеск 💦.
	local function hopRider(to: number)
		local rider = ui.rider
		if not rider.Visible then
			return
		end
		stopRiderWiggle()
		local from = rider.Position.X.Scale
		local y = defaults.riderY
		local quad = Enum.EasingStyle.Quad
		UiFx.tween(rider, 0.1, { Position = UDim2.fromScale((from + to) / 2, y - 0.9) }, quad, Enum.EasingDirection.Out)
		UiFx.tween(rider, 0.2, { Rotation = rider.Rotation + 360 }, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
		later(phaseTrove, 0.1, function()
			UiFx.tween(rider, 0.1, { Position = UDim2.fromScale(to, y) }, quad, Enum.EasingDirection.In)
		end)
		later(phaseTrove, 0.2, function()
			startRiderWiggle()
			UiFx.bump(rider, 1.25, 0.25)
			UiFx.floatText(ui.track, "💦", {
				position = UDim2.fromScale(to, -0.45),
				size = UDim2.fromScale(0.1, 0.9),
				rise = 0.5,
				time = 0.45,
				z = 5,
			})
		end)
	end

	-- Слово редкости над панелью уступает слову попадания, промаха или победы (и уходит с
	-- мини-игрой): вспухает и тает за 0.12 с — два слова в одной полосе не складываются.
	local function knockRarityWord()
		local word = rarityWordLabel
		rarityWordLabel = nil
		if not word or word.Parent == nil then
			return
		end
		local quad, out = Enum.EasingStyle.Quad, Enum.EasingDirection.Out
		local scale = word:FindFirstChildOfClass("UIScale")
		if scale then
			UiFx.tween(scale, 0.12, { Scale = 1.3 }, quad, out)
		end
		UiFx.tween(word, 0.12, { TextTransparency = 1 }, quad, out)
		local outline = word:FindFirstChild("Outline")
		if outline and outline:IsA("UIStroke") then
			UiFx.tween(outline, 0.12, { Transparency = 1 }, quad, out)
		end
		task.delay(0.13, function()
			word:Destroy()
		end)
	end

	-- Слово редкости над панелью (легендарная, мифическая): один раз в начале — огромное, в цветах
	-- редкости (мифическая — радуга вдоль букв), поднимается и тает над панелью. Ни нажатий, ни
	-- стрелки с зоной не закрывает: оно выше панели и ничего не ловит. Первое же слово попадания
	-- (промаха, победы) его сбивает (knockRarityWord).
	local function rarityWord(mg: Minigame)
		local rarity = FishingRules.GetRarity(mg.Rarity)
		local style = UIConfig.Rarity[mg.Rarity] or UIConfig.Rarity.Common
		local panel = ui.minigame
		local root = ui.fishing
		local area = root.AbsoluteSize
		if not rarity or area.Y < 2 then
			return
		end
		local height = 0.2 * area.Y
		local top = panel.AbsolutePosition - root.AbsolutePosition
		-- Над панелью и не шире её (на телефоне она прижата влево — слово не уходит за край экрана).
		local width = math.min(0.62 * area.X, panel.AbsoluteSize.X * 1.1)
		local cx = math.clamp(top.X + panel.AbsoluteSize.X / 2, width / 2 + 8, area.X - width / 2 - 8)
		-- ART-03: и не на своём рыбаке (панель у него сбоку или под ним) — в сторону от него, не
		-- шире просвета (тогда и ниже ростом).
		local fisher = fisherRect()
		if fisher and fisher.y0 < top.Y + height * 0.3 and fisher.y1 > top.Y - height - 0.06 * area.Y then
			local lo, hi = 8, area.X - 8
			if (fisher.x0 + fisher.x1) / 2 >= cx then
				hi = math.min(hi, fisher.x0 - 8)
			else
				lo = math.max(lo, fisher.x1 + 8)
			end
			if hi - lo < width and hi > lo then
				height *= (hi - lo) / width
				width = hi - lo
			end
			cx = math.clamp(cx, lo + width / 2, math.max(lo + width / 2, hi - width / 2))
		end
		local y = (top.Y - height * 0.45) / area.Y
		-- v3: на телефоне панель стоит прямо под плашкой базы — слово не налезает на плашку и её
		-- флажок (ART-04; наклон −4° задирает правый край): оно ниже (заходит на верх панели, где
		-- та же редкость) и мельче, почти не поднимается.
		local ceiling = 0
		for _, box in statusBoxes() do
			if math.abs((box.x0 + box.x1) / 2 - cx) < (box.x1 - box.x0 + width) / 2 then
				ceiling = math.max(ceiling, box.y1 + 4 + math.sin(math.rad(4)) * width / 2)
			end
		end
		local rise = 0.06
		if top.Y - height * 0.95 < ceiling then
			local fit = math.clamp(top.Y + height * 0.3 - ceiling, height * 0.6, height)
			y = (ceiling + fit / 2) / area.Y
			height, rise = fit, 0.01
		end
		-- «Удар» сверху (2.2 → 1) — от края, дальнего от рыбака, если от середины он лёг бы на него.
		local keepouts = {}
		if fisher then
			table.insert(keepouts, fisher)
		end
		local cy = y * area.Y
		local pivot, from = Layout.slamPivot(
			Layout.rect(cx - width / 2, cy - height / 2, cx + width / 2, cy + height / 2),
			2.2,
			keepouts
		)
		local word = UiFx.floatText(root, `{upper(rarity.Name)}!`, {
			position = UDim2.fromScale((cx + (pivot.X - 0.5) * width) / area.X, y),
			anchor = pivot,
			size = UDim2.fromScale(width / area.X, height / area.Y),
			colors = if style.Rainbow then UIConfig.Rainbow else { WHITE, style.Top, style.Bottom },
			rise = rise,
			time = RARITY_WORD_TIME,
			rotate = -4,
			z = 13,
		})
		word.Active = false
		knockRarityWord()
		rarityWordLabel = word
		phaseTrove:Add(knockRarityWord)
		local gradient = word:FindFirstChild("TextFill")
		if style.Rainbow and gradient and gradient:IsA("UIGradient") then
			gradient.Rotation = 0
		end
		local scale = word:FindFirstChildOfClass("UIScale")
		if scale then
			scale.Scale = from -- «удар» сверху, как «ИДЕАЛЬНО!»
			UiFx.tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		end
	end

	-- Редкая — лёгкая обводка панели (Rare, медленно «дышит»). Эпическая и выше: обводка панели в
	-- цвет редкости (легендарная — с золотым бликом по кругу, мифическая — вращающаяся радуга),
	-- лучи за панелью, края экрана «дышат» цветом редкости; легендарная и мифическая — ещё «удар»
	-- заголовка со вспышкой, слово редкости над панелью и стук сердца.
	local function minigameAura(mg: Minigame)
		local rank = RARITY_RANK[mg.Rarity] or 1
		if rank < 2 then
			return
		end
		local style = UIConfig.Rarity[mg.Rarity] or UIConfig.Rarity.Common
		local aura, fill = ui.aura, ui.auraFill
		aura.Enabled = true
		if rank == 2 then
			fill.Color = ColorSequence.new(WHITE, style.Top)
			fill.Rotation = 90
			aura.Transparency = 0.15
			local breathe = TweenService:Create(
				aura,
				TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Transparency = 0.6 }
			)
			breathe:Play()
			phaseTrove:Add(function()
				breathe:Cancel()
				aura.Transparency = 0
				aura.Enabled = false
				fill.Rotation = 0
			end)
			return
		end
		local loop: Tween? = nil
		if style.Rainbow then
			fill.Color = UiFx.sequence(UIConfig.Rainbow)
			fill.Rotation = 0
			loop = TweenService:Create(
				fill,
				TweenInfo.new(2, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1),
				{ Rotation = 360 }
			)
		elseif rank >= 4 then
			fill.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Palette.Gold.Bottom),
				ColorSequenceKeypoint.new(0.4, Palette.Gold.Top),
				ColorSequenceKeypoint.new(0.5, WHITE),
				ColorSequenceKeypoint.new(0.6, Palette.Gold.Top),
				ColorSequenceKeypoint.new(1, Palette.Gold.Bottom),
			})
			fill.Rotation = 0
			fill.Offset = Vector2.new(-1, 0)
			loop = TweenService:Create(
				fill,
				TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1),
				{ Offset = Vector2.new(1, 0) }
			)
		else
			fill.Color = ColorSequence.new(style.Top, style.Bottom)
			fill.Rotation = 90
		end
		if loop then
			loop:Play()
		end
		phaseTrove:Add(function()
			if loop then
				loop:Cancel()
			end
			aura.Enabled = false
			fill.Rotation = 0
			fill.Offset = Vector2.zero
		end)
		phaseTrove:Add(UiFx.rays(ui.minigame, {
			colors = style.Rays,
			count = 12,
			size = 1.9,
			transparency = 0.55,
			speed = 30,
			halo = false,
			breathe = false,
		}))
		-- Узкие полосы (AURA_EDGE экрана): виньетка живёт всю мини-игру — бережём заливку на телефоне
		-- (у легендарной и мифической — после вспышки входа, чтобы не сложились).
		local edge: Color3 | { Color3 } = if style.Rainbow
			then { UIConfig.Rainbow[1], UIConfig.Rainbow[7] }
			else style.Top
		local stopEdge: ((number?) -> ())? = nil
		auraEdge = true
		later(phaseTrove, if rank >= 4 then 0.35 else 0, function()
			stopEdge = UiFx.edgeVignette(ui.hud, edge, 0.85, 0.9, { pulseTo = 0.65, fadeIn = 0.5, size = AURA_EDGE })
		end)
		phaseTrove:Add(function()
			auraEdge = false
			if stopEdge then
				stopEdge()
			end
		end)
		if rank >= 4 then
			UiFx.slam(ui.title, 2.2, 0.35)
			UiFx.flash(ui.hud, style.Top, 0.3, 0.7)
			rarityWord(mg)
			every(phaseTrove, 0.8, function()
				UiFx.sound("splash", 0.2, 0.5)
			end, 0.4)
		end
	end

	function showMinigame(mg: Minigame)
		clearEventHint() -- колонка внизу — для мини-игры
		layoutColumn()
		minigamesShown += 1
		cueOn = minigamesShown <= CUE_MINIGAMES and keyHint == "" -- (с клавишей на кнопке — без 👇)
		predictedHit = nil
		needleHoldUntil = 0
		local rarity = FishingRules.GetRarity(mg.Rarity)
		ui.title.Text = `{upper(if rarity then rarity.Name else "Неизвестная")} РЫБА!`
		styleTitle(mg.Rarity)
		refreshPips(mg)
		-- Зона по ширине с первого кадра такая, какой её проверяет сервер; «вырастает» по высоте.
		ui.zone.Position = UDim2.fromScale(mg.ZoneCenter, 0.5)
		ui.zone.Size = UDim2.fromScale(mg.ZoneWidth, 0)
		UiFx.tween(
			ui.zone,
			0.3,
			{ Size = UDim2.fromScale(mg.ZoneWidth, defaults.zoneHeight) },
			Enum.EasingStyle.Back,
			Enum.EasingDirection.Out,
			0.08
		)
		ui.zoneFlash.BackgroundTransparency = 1
		-- Короткий экран (телефон): панель встаёт СЛЕВА от своего рыбака (v3: борьба — упор, катушка,
		-- согнутая удочка — видна целиком); планшет и ПК: внизу по центру, а если там она легла бы
		-- на рыбака — тоже слева, целиком меньше (MINI_DOCK_MIN, UX-01), или сбоку внизу. И не на свой
		-- поплавок (рывки, пена, брызги видны); не хватает места — как обычно, внизу по центру.
		local panel = ui.minigame
		local restSize = panel.Size
		panel.Position = defaults.minigamePosition
		local short = ui.hud.AbsoluteSize.Y < SHORT_SCREEN
		local position, size = keepClearOfBobber(
			panel,
			defaults.minigamePosition,
			restSize,
			REEL_DIVE,
			if short then math.huge else MINI_DOCK_MIN,
			true
		)
		if position ~= panel.Position or size ~= restSize then
			panel.Position, panel.Size = position, size
			phaseTrove:Add(function()
				panel.Position = defaults.minigamePosition
				panel.Size = restSize
			end)
		end
		updateMinigameFrame()
		ui.minigame.Visible = true
		-- Панель «приземляется» на место (падает на несколько px и сплющивается), ободок вспыхивает,
		-- заголовок «ударяет» (у легендарной и мифической — свой «удар» сверху, minigameAura).
		UiFx.popIn(ui.minigame, { from = 0.8, time = 0.25 })
		UiFx.snapIn(ui.minigame, { drop = 10 })
		UiFx.rimFlash(ui.minigame, { delay = 0.12 })
		if (RARITY_RANK[mg.Rarity] or 1) < 4 then
			UiFx.punch(ui.title, { from = 0.6, peak = 1.12, delay = 0.1 })
		end
		for index, pip in ui.pips do
			if pip.Visible then
				local star = pip:FindFirstChild("Star")
				if star and star:IsA("GuiObject") then
					UiFx.popIn(star, { from = 0, time = 0.3, delay = 0.1 + index * 0.06 })
				end
			end
		end
		phaseTrove:Connect(RunService.RenderStepped, updateMinigameFrame)

		-- Шлейф стрелки: четыре белые с голубым отливом копии ПОД зоной, вплотную друг к другу (одна
		-- полоса, а не лишние стрелки), уже стрелки и всё прозрачнее к хвосту (0.2 → 0.75) — яркая
		-- полоса скорости на тёмной канавке (зону не закрывают; короче стрелки и без обводки).
		phaseTrove:Add(UiFx.trail(ui.needle, {
			count = 4,
			lag = 0.015,
			transparency = 0.2,
			last = 0.75,
			color = UIConfig.Fishing.NeedleGhost,
			width = 0.9,
			taper = 0.5,
			height = 0.6,
			z = 2,
		}))
		-- Свет под зоной «дышит» — только по высоте (по ширине зона не врёт).
		local glow = ui.zoneGlow
		local glowRest = defaults.glowSize
		glow.Size = glowRest
		local breathe = TweenService:Create(
			glow,
			TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Size = UDim2.new(glowRest.X.Scale, glowRest.X.Offset, glowRest.Y.Scale * 1.25, glowRest.Y.Offset) }
		)
		breathe:Play()
		phaseTrove:Add(function()
			breathe:Cancel()
			glow.Size = glowRest
		end)

		showRider(mg)
		-- Тач-экран: касание панели — тоже нажатие.
		ui.tapPad.Visible = UserInputService.TouchEnabled
		-- Новичку: 👇 «нажимает» кнопку, пока стрелка в зоне (видимость — каждый кадр).
		if cueOn then
			bounceCue(phaseTrove)
		end
		phaseTrove:Add(function()
			ui.tapPad.Visible = false
			ui.tapCue.Visible = false
		end)
		minigameAura(mg)
	end

	-- Точка на полосе (доля 0..1) в долях панели мини-игры: центр по высоте полосы.
	local function trackPoint(u: number): Vector2
		return Vector2.new(defaults.trackLeft + u * defaults.trackWidth, defaults.trackMidY)
	end

	-- Слово попадания над зоной: выскакивает 0 → 1.3 → 1 и поднимается; «ИДЕАЛЬНО!» — «удар»
	-- 2 → 1 и белый блик по золотым буквам; «МЕГА!» — радуга вдоль букв.
	local function hitWord(word: HitWord, x: number, perfect: boolean)
		knockRarityWord()
		local panel = ui.minigame
		local h = if perfect then 0.62 else 0.55
		-- (Не на рыбаке и на пике выскакивания 1.3, не на статусе — wordSpot; «ИДЕАЛЬНО!» — «удар»
		-- от края, дальнего от рыбака, если от середины он лёг бы на него.)
		local px, py, rise =
			wordSpot(panel, math.clamp(x, 0.36, 0.64), -0.14, 0.7, h, 0.35, 4, if perfect then 1 else 1.3)
		local pivot, from = Vector2.new(0.5, 0.5), 2
		local fisher = fisherRect()
		if perfect and fisher then
			local size = panel.AbsoluteSize
			local at = panel.AbsolutePosition - ui.fishing.AbsolutePosition
			local cx, cy = at.X + px * size.X, at.Y + py * size.Y
			local hw, hh = 0.35 * size.X, h / 2 * size.Y
			pivot, from = Layout.slamPivot(Layout.rect(cx - hw, cy - hh, cx + hw, cy + hh), 2, { fisher })
		end
		local label = UiFx.floatText(panel, word.text, {
			position = UDim2.fromScale(px + (pivot.X - 0.5) * 0.7, py),
			anchor = pivot,
			size = UDim2.fromScale(0.7, h),
			colors = word.colors,
			rise = rise,
			time = 0.85,
			rotate = if perfect then -4 else nil,
			z = 8,
		})
		local gradient = label:FindFirstChild("TextFill")
		local scale = label:FindFirstChildOfClass("UIScale")
		if word.rainbow and gradient and gradient:IsA("UIGradient") then
			gradient.Rotation = 0
		end
		if not scale then
			return
		end
		if perfect then
			scale.Scale = from
			UiFx.tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			if gradient and gradient:IsA("UIGradient") then
				gradient.Rotation = 20
				gradient.Offset = Vector2.new(-1, 0)
				UiFx.tween(
					gradient,
					0.5,
					{ Offset = Vector2.new(1, 0) },
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.InOut,
					0.15
				)
			end
		else
			scale.Scale = 0
			UiFx.tween(scale, 0.12, { Scale = 1.3 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			task.delay(0.12, function()
				if scale.Parent then
					UiFx.tween(scale, 0.13, { Scale = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				end
			end)
		end
	end

	-- «ИДЕАЛЬНО!»: 8 ⭐ разлетаются от зоны, панель на миг вспыхивает белым, края экрана —
	-- золотом, камера на миг «приближается».
	local function perfectBurst(origin: Vector2)
		local panel = ui.minigame
		local size = panel.AbsoluteSize
		local aspect = if size.X > 1 then size.Y / size.X else 0.35
		for index = 1, 8 do
			local star = Instance.new("TextLabel")
			star.Name = "FxStar"
			star.BackgroundTransparency = 1
			star.Text = "⭐"
			star.TextScaled = true
			star.AnchorPoint = Vector2.new(0.5, 0.5)
			star.SizeConstraint = Enum.SizeConstraint.RelativeYY
			local s = 0.12 + 0.025 * (index % 3)
			star.Size = UDim2.fromScale(s, s)
			star.Position = UDim2.fromScale(origin.X, origin.Y)
			star.Rotation = (index * 37) % 50 - 25
			star.ZIndex = 8
			star.Parent = panel
			local angle = math.rad(index * 45 + 20)
			local reach = 0.62
			local target =
				UDim2.fromScale(origin.X + math.cos(angle) * reach * aspect, origin.Y + math.sin(angle) * reach)
			UiFx.tween(
				star,
				0.55,
				{ Position = target, Rotation = star.Rotation + 140 },
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			)
			UiFx.tween(star, 0.25, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.32)
			task.delay(0.6, function()
				star:Destroy()
			end)
		end
		local flash = Instance.new("Frame")
		flash.Name = "FxPanelFlash"
		flash.BackgroundColor3 = WHITE
		flash.BackgroundTransparency = 0.35
		flash.BorderSizePixel = 0
		flash.Size = UDim2.fromScale(1, 0.95)
		flash.ZIndex = 7
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.2, 0)
		corner.Parent = flash
		flash.Parent = panel
		UiFx.tween(flash, 0.12, { BackgroundTransparency = 1 })
		task.delay(0.14, function()
			flash:Destroy()
		end)
		if not auraEdge then
			UiFx.edgeVignette(ui.hud, Palette.Gold.Top, 0.8, nil, { fadeIn = 0, hold = 0, size = AURA_EDGE })
		end
		UiFx.fovPunch(-3, 0.05, 0.15)
	end

	-- Удар попадания (сразу по нажатию — сервер судит по тому же t): стрелка на миг замирает и
	-- вспыхивает золотом, панель вздрагивает, зона вспыхивает, крупные искры над панелью, слово
	-- (от попадания к попаданию громче), звук всё выше, кнопка подпрыгивает.
	function punchHit(mg: Minigame, index: number, perfect: boolean, tapU: number, zoneCenter: number)
		local word = if perfect
			then HIT_PERFECT
			elseif index >= 3 then HIT_MEGA
			elseif index == 2 then HIT_NEXT
			else HIT_FIRST
		local origin = trackPoint(zoneCenter)
		needleHoldUntil = os.clock() + NEEDLE_HOLD
		needleHoldAt = tapU
		ui.needle.BackgroundColor3 = Palette.Gold.Top
		UiFx.tween(ui.needle, 0.15, { BackgroundColor3 = WHITE })
		UiFx.bump(ui.minigame, 1.06, 0.18)
		if index == 2 and not perfect then
			UiFx.shake(ui.minigame, 3 / math.max(ui.hud.AbsoluteSize.X, 1), 0.2) -- ±3 px
		end
		ui.zoneFlash.BackgroundTransparency = 0.2
		UiFx.tween(ui.zoneFlash, 0.2, { BackgroundTransparency = 1 })
		UiFx.glowRing(ui.zone, {
			color = if perfect then Palette.Gold.Top else WHITE,
			scale = if perfect then 1.8 else 1.5,
			thickness = 3,
			time = 0.45,
		})
		phaseTrove:Add(UiFx.burst(ui.minigame, {
			origin = origin,
			count = if perfect then 24 else 18,
			colors = if perfect
				then { WHITE, Palette.Gold.Top, Palette.Sun.Top, Palette.Berry.Top }
				else { WHITE, Palette.Leaf.Top, Palette.Gold.Top },
			power = if perfect then 1.7 else 1.4,
			size = 2.4,
			z = 8,
		}))
		hitWord(word, origin.X, perfect)
		UiFx.sound("pop", if perfect then 0.6 else 0.5, if perfect then 1.25 else 1 + 0.15 * index)
		UiFx.bump(ui.actionButton, math.min(1.12, (ui.actionButton:GetAttribute("GrowMax") :: number?) or 2), 0.3)
		if perfect then
			perfectBurst(origin)
			UiFx.flashText(ui.title, Palette.Gold.Top, 0.4) -- заголовок вспыхивает золотом
		end
	end

	-- Победное нажатие (сервер судит по тому же t — ответ ещё в пути): не удар, а «замирание» —
	-- стрелка золотая стоит там, где нажали, зона горит золотом, от неё кольцо, панель чуть
	-- вздрагивает, звук выше. Держится до ответа ("Caught" — копия мини-игры «побеждает» с этой
	-- стрелкой; "Lost" — промах), но не дольше WIN_HOLD; пока predictedHit = HitsNeeded, нажатия
	-- не отправляются (tap).
	local WIN_HOLD = 1.5
	function holdWin(u: number)
		needleHoldUntil = os.clock() + WIN_HOLD
		needleHoldAt = u
		local needle, flash = ui.needle, ui.zoneFlash
		local flashColor = flash.BackgroundColor3
		needle.BackgroundColor3 = Palette.Gold.Top
		flash.BackgroundColor3 = Palette.Gold.Top
		flash.BackgroundTransparency = 0.15
		UiFx.glowRing(ui.zone, { color = Palette.Gold.Top, scale = 1.6, thickness = 3, time = 0.35 })
		UiFx.bump(ui.minigame, 1.04, 0.12)
		UiFx.sound("pop", 0.5, 1.4)
		local function release()
			needleHoldUntil = 0
			needle.BackgroundColor3 = WHITE
			flash.BackgroundColor3 = flashColor
			flash.BackgroundTransparency = 1
		end
		-- Ответа нет (сервер не засчитал нажатие): игра идёт дальше.
		later(phaseTrove, WIN_HOLD, function()
			release()
			predictedHit = nil
		end)
		phaseTrove:Add(release)
	end

	-- Ответ сервера на попадание ("Zone"): зона на новом месте «вырастает» по высоте, 🐟 прыгает
	-- за ней, ⭐ «печатается» в кружке попадания (от 2 до 1, с искрами). Если удар не был
	-- предсказан (нажатие не отсюда / зона уже ждала ответа) — он играется сейчас.
	function celebrateHit(mg: Minigame, oldCenter: number, predicted: boolean)
		if not predicted then
			local perfect = tapNeedle ~= nil
				and tapZone ~= nil
				and math.abs(tapNeedle - tapZone) <= mg.ZoneWidth * PERFECT_SHARE
			punchHit(mg, mg.Hits, perfect, tapNeedle or oldCenter, oldCenter)
		end
		ui.zone.Size = UDim2.fromScale(mg.ZoneWidth, defaults.zoneHeight * 0.3)
		UiFx.tween(
			ui.zone,
			0.3,
			{ Size = UDim2.fromScale(mg.ZoneWidth, defaults.zoneHeight) },
			Enum.EasingStyle.Back,
			Enum.EasingDirection.Out
		)
		UiFx.glowRing(ui.zone, { color = Palette.Leaf.Top, scale = 1.4, thickness = 3, time = 0.4 })
		hopRider(mg.ZoneCenter)
		local pip = ui.pips[mg.Hits]
		local star = pip and pip:FindFirstChild("Star")
		if star and star:IsA("GuiObject") then
			local scale = UiFx.scaleOf(star)
			scale.Scale = 2
			UiFx.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			UiFx.wiggle(star, 20, 2, 0.35)
			phaseTrove:Add(UiFx.burst(ui.minigame, {
				origin = pipPoint(mg.Hits, math.clamp(mg.HitsNeeded, 1, #ui.pips)),
				count = 6,
				colors = { WHITE, Palette.Gold.Top, Palette.Leaf.Top },
				power = 0.45,
				time = 0.45,
				z = 8,
			}))
		end
		UiFx.sound("tick", 0.3, 1.5)
	end

	-- Промах / время вышло: мини-игра закрывается сразу, а её копия ещё полсекунды краснеет,
	-- качается и показывает надпись (рыба уплывает за край), потом быстро уходит вверх, сжимается
	-- и тает — вся за MISS_HOLD, до подсказки с причиной.
	function missGhost(text: string)
		local source = ui.minigame
		if not source.Visible then
			return
		end
		knockRarityWord()
		local ghost = ghostOf(source, "FxMinigameMiss")
		local track = ghost:FindFirstChild("Track")
		if track and track:IsA("GuiObject") then
			local flash = Instance.new("Frame")
			flash.Name = "FxMissFlash"
			flash.BackgroundColor3 = Palette.Berry.Top
			flash.BackgroundTransparency = 0.2
			flash.BorderSizePixel = 0
			flash.Size = UDim2.fromScale(1, 1)
			flash.ZIndex = 9
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.4, 0)
			corner.Parent = flash
			flash.Parent = track
			UiFx.tween(flash, 0.5, { BackgroundTransparency = 1 })
			local zone = track:FindFirstChild("Zone")
			if zone and zone:IsA("GuiObject") then
				UiFx.recolor(zone, "Berry", 0.12) -- зона «краснеет» (перетекает в красный)
				local halo = zone:FindFirstChild("Glow") -- … и её зелёный ореол гаснет с ней
				if halo and halo:IsA("GuiObject") then
					UiFx.tween(halo, 0.12, { BackgroundTransparency = 1 })
				end
				local zoneFlash = zone:FindFirstChild("Flash")
				if zoneFlash and zoneFlash:IsA("GuiObject") then
					zoneFlash.BackgroundTransparency = 1 -- без золота «победного» нажатия (holdWin)
				end
			end
			local rider = track:FindFirstChild("Rider")
			if rider and rider:IsA("TextLabel") and rider.Visible then
				local quad, inDir = Enum.EasingStyle.Quad, Enum.EasingDirection.In
				UiFx.tween(
					rider,
					0.3,
					{ Position = UDim2.fromScale(1.12, rider.Position.Y.Scale), Rotation = 30 },
					quad,
					inDir
				)
				UiFx.tween(rider, 0.3, { TextTransparency = 1 }, quad, inDir)
			end
		end
		UiFx.wiggle(ghost, 4, 3, 0.4)
		local wx, wy, rise = wordSpot(ghost, 0.5, -0.14, 0.62, 0.5, 0.2, 6, 1) -- (не на флажке базы, ART-04)
		UiFx.floatText(ghost, text, {
			position = UDim2.fromScale(wx, wy),
			size = UDim2.fromScale(0.62, 0.5),
			colors = { Palette.Berry.Top, Palette.Berry.Bottom },
			rise = rise,
			time = MISS_HOLD,
			rotate = -6,
			z = 8,
		})
		UiFx.sound("tick", 0.4)
		UiFx.sound("pop", 0.35, 0.6)
		-- Уходит быстро и целиком до подсказки (она выскакивает в той же колонке через MISS_HOLD):
		-- две красные плашки друг на друге не стоят.
		local exit = 0.2
		task.delay(MISS_HOLD - exit, function()
			if ghost.Parent == nil then
				return
			end
			local quad, inDir = Enum.EasingStyle.Quad, Enum.EasingDirection.In
			UiFx.tween(ghost, exit, { Position = ghost.Position - UDim2.fromScale(0, 0.08) }, quad, inDir)
			UiFx.tween(UiFx.scaleOf(ghost), exit, { Scale = 0.6 }, quad, inDir)
			UiFx.fadeOut(ghost, exit)
			task.delay(exit, function()
				ghost:Destroy()
			end)
		end)
	end
end

--------------------------------------------------------------------------------
-- Действие игрока: забросить / подсечь / тянуть / закрыть карточку
--------------------------------------------------------------------------------

-- Своё тело рыбака отвечает на нажатие сразу, не дожидаясь сервера (FisherAnimController.Cue:
-- "castPress" — замах, "hookPress" — подсечка, в мини-игре "tapHit" / "tapWin" — рывок удочкой
-- на предсказанное попадание, "tapMiss" — удочка клюнула вниз). Модуль берётся при первом вызове.
local function fisherCue(name: string)
	local module = script.Parent and script.Parent:FindFirstChild("FisherAnimController")
	local ok, anim = pcall(function(): any
		return if module and module:IsA("ModuleScript") then require(module) :: any else nil
	end)
	if ok and anim and type(anim.Cue) == "function" then
		pcall(anim.Cue, name)
	end
end

local function tap(now: number)
	-- Сервер не примет чаще TapInterval — по своим часам: с запасом TAP_SLACK на разброс сети
	-- нажатие, отправленное «впритык», не потеряется молча.
	local TAP_SLACK = 0.03
	if now - lastTap < FishingConfig.TapInterval + TAP_SLACK then
		return
	end
	lastTap = now
	local mg = minigame
	if mg then
		if predictedHit == mg.HitsNeeded then
			return -- победное нажатие уже сделано: стрелка стоит, ждём ответа сервера (holdWin)
		end
		local u = FishingRules.Needle(mg.U0, mg.Speed, now - minigameStart)
		tapNeedle = u
		tapZone = mg.ZoneCenter
		-- Попадание видно сразу: сервер судит по этому же t. Не предсказываем победное (это
		-- начало карточки улова — onCaught) и пока ждём новую зону (сервер не засчитает старую);
		-- промах решает сервер ("Lost" → копия мини-игры краснеет, даже после удара).
		if
			predictedHit == nil
			and mg.Hits + 1 < mg.HitsNeeded
			and FishingRules.IsHit(u, mg.ZoneCenter, mg.ZoneWidth)
		then
			local predicted = mg.Hits + 1
			predictedHit = predicted
			punchHit(mg, predicted, math.abs(u - mg.ZoneCenter) <= mg.ZoneWidth * PERFECT_SHARE, u, mg.ZoneCenter)
			fisherCue("tapHit")
			-- Сервер может молча не засчитать нажатие (раньше TapInterval по его часам, после
			-- прощённого промаха…): без ответа за MaxLag + 0.2 с предсказание забывается, иначе
			-- следующее настоящее попадание осталось бы без удара.
			later(phaseTrove, FishingConfig.MaxLag + 0.2, function()
				if predictedHit == predicted then
					predictedHit = nil
				end
			end)
		end
		-- Победное — не удар, а «замирание» до ответа сервера (holdWin; праздник — в onCaught).
		if
			predictedHit == nil
			and mg.Hits + 1 == mg.HitsNeeded
			and FishingRules.IsHit(u, mg.ZoneCenter, mg.ZoneWidth)
		then
			predictedHit = mg.HitsNeeded
			holdWin(u)
			fisherCue("tapWin")
		elseif predictedHit == nil and not FishingRules.IsHit(u, mg.ZoneCenter, mg.ZoneWidth) then
			fisherCue("tapMiss") -- (промах решит сервер; тело отвечает сразу)
		end
	end
	Net.Event("FishingTap"):FireServer(now - minigameStart)
end

-- Взять удочку из рюкзака в руку.
local function takeRod()
	local tool = backpackRod()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if tool and humanoid then
		humanoid:EquipTool(tool)
	end
end

-- Тап по самой карточке улова: пропустить доли или закрыть (tapCard; действие — см. doAction).
local function tryCloseCard()
	tapCard()
end

-- fromButton: нажатие пришло с самой кнопки (её сжимает UiFx.press); клавиша и тап удочкой
-- по миру «нажимают» кнопку анимацией здесь.
local function doAction(fromButton: boolean?)
	local now = os.clock()
	local previous = lastAction
	if now - previous < ACTION_DEBOUNCE then
		return
	end
	lastAction = now
	local button = ui.actionButton
	if not fromButton and button.Visible then
		UiFx.bump(button, 0.88, 0.25)
		whiteRings(0, true) -- рябь (не дотягивается до кнопки прыжка)
	end
	if catchScreen then
		-- Доли не пропускает (это делает тап по карточке); показанную целиком карточку закрывает,
		-- если это не «ЛОВИ!» по инерции (tapCard смотрит, сколько прошло с прошлого нажатия).
		tapCard(now - previous)
	elseif not rod then
		if offerTake then
			takeRod()
		end
	elseif phase == "Idle" then
		if now < castReadyAt then
			return -- кулдаун заброса: кнопка тусклая, сервер всё равно откажет
		end
		if isFar() then
			pointToSpot() -- «КУДА ИДТИ?»: сервер всё равно откажет — показываем дорогу
			return
		end
		Net.Event("FishingCast"):FireServer()
		startPending()
		UiFx.sound("swoosh", 0.35)
		fisherCue("castPress")
	elseif phase == "Bite" then
		if not hookSent then
			hookSent = true
			Net.Event("FishingHook"):FireServer()
			fisherCue("hookPress")
			actionPulseTrove:Clean() -- подсечка принята: кнопка гаснет до мини-игры
			local ring = button:FindFirstChild("FxRingTimer") -- кольцо-таймер поклёвки — больше не нужно
			if ring then
				ring:Destroy()
			end
			ui.tapCue.Visible = false
			refreshButtons()
			UiFx.bump(ui.biteAlert, 1.15, 0.25)
		end
	elseif phase == "Reeling" then
		tap(now)
	end
end

local function onActionInput(_name: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		doAction(false)
	end
	return Enum.ContextActionResult.Sink
end

-- «ВЗЯТЬ» на кнопке — её жмут и клавиши: 1 (как прежняя панель предметов Roblox: её нет —
-- HudController), F и R2 (как все действия кнопки). Только пока «ВЗЯТЬ» на кнопке
-- (refreshContextHint); с удочкой в руке F / R2 — снова ACTION_NAME, а 1 убирает её (equipRod).
function bindTakeKeys(on: boolean)
	if on then
		ContextActionService:BindAction(
			TAKE_ACTION,
			onActionInput,
			false,
			Enum.KeyCode.One,
			Enum.KeyCode.F,
			Enum.KeyCode.ButtonR2
		)
	else
		ContextActionService:UnbindAction(TAKE_ACTION)
	end
end

local function requestStop()
	-- Рыба на крючке — не сматываем (кнопка в это время спрятана; тап мог прийти, пока она уходила).
	if not isLineOut() or phase == "Bite" or phase == "Reeling" then
		return
	end
	Net.Event("FishingStop"):FireServer()
	endSession() -- сервер подтвердит "Idle" { Reason = "stop" }
end

--------------------------------------------------------------------------------
-- Ответы сервера (FishingState)
--------------------------------------------------------------------------------

-- Наружу из раздела (блок do … end, см. «Устройство файла» в шапке):
local onFishingState
do
	-- Почему рыба ушла / почему рыбалка закончилась: общие с сервером тексты по коду причины
	-- (FishingConfig.Texts; сервер присылает и сам текст — он важнее). Причины без текста — молча.
	local LOST_TEXT: { [string]: string } = TEXTS.Lost

	local IDLE_TEXT: { [string]: string } = TEXTS.Idle

	--[[
		Ожидание поклёвки «живое»: 1–2 раза за ожидание рыба «пробует» наживку (только на этом
		клиенте, через NIBBLE_FROM..NIBBLE_TO с после заброса — поплавок уже на воде (замах
		CastWindUp + полёт), поклёвка не раньше BiteDelay.Min):
		кнопка вздрагивает и качается, над ней всплывает «?», поплавок в мире притапливается
		(FishingFxController.Nibble). Нажатия в это время по-прежнему ничего не отправляют.
	]]
	local NIBBLE_FROM, NIBBLE_TO = 0.8 + FishingConfig.CastWindUp, 1.9 + FishingConfig.CastWindUp
	local nibbleRandom = Random.new()
	local fishingFx: any = nil -- FishingFxController (берётся при первой «примерке»), false — нет

	local function nibbleWorld()
		if fishingFx == nil then
			local module = script.Parent and script.Parent:FindFirstChild("FishingFxController")
			local ok, controller = pcall(function(): any
				return if module and module:IsA("ModuleScript") then require(module) :: any else nil
			end)
			fishingFx = if ok and controller then controller else false
		end
		if fishingFx and type(fishingFx.Nibble) == "function" then
			pcall(fishingFx.Nibble)
		end
	end

	local function nibble()
		local button = ui.actionButton
		if phase ~= "Waiting" or not button.Visible then
			return
		end
		-- Кнопка вздрагивает, поплавок на ней качается (качается не вся кнопка: справа кнопка прыжка).
		UiFx.bump(button, 0.94, 0.3)
		UiFx.wiggle(ui.actionBobber, 14, 2, 0.35)
		-- «?» — над левым плечом кнопки: справа кнопка прыжка.
		UiFx.floatText(button, "?", {
			position = UDim2.fromScale(0.22, 0.1),
			size = UDim2.fromScale(0.42, 0.42),
			rise = 0.14,
			time = 0.4,
			rotate = -12,
			z = 12,
		})
		UiFx.sound("tick", 0.25, 1.6)
		nibbleWorld()
	end

	local waitedOnce = false -- v3 (UIM-09): самое первое ожидание за игру — подсказка, что делать
	local function onWaiting(_data: { [string]: any })
		hookSent = false
		setPhase("Waiting")
		if not waitedOnce then
			waitedOnce = true
			showHint("Жди, пока клюнет — потом жми!", "info")
		end
		local first = nibbleRandom:NextNumber(NIBBLE_FROM, NIBBLE_TO - 0.5)
		later(phaseTrove, first, nibble)
		if nibbleRandom:NextNumber() < 0.5 then
			later(phaseTrove, math.min(first + nibbleRandom:NextNumber(0.35, 0.6), NIBBLE_TO), nibble)
		end
	end

	local function onBite(data: { [string]: any })
		enterBite(number(data.Window, FishingConfig.BiteWindow))
	end

	local function onMinigame(data: { [string]: any })
		local rarity = if typeof(data.Rarity) == "string" then data.Rarity else "Common"
		local rule = FishingRules.GetMinigameRule(rarity)
		local mg: Minigame = {
			Rarity = rarity,
			U0 = number(data.U0, 0),
			Speed = number(data.Speed, rule.Speed),
			ZoneCenter = number(data.ZoneCenter, 0.5),
			ZoneWidth = number(data.ZoneWidth, rule.ZoneWidth),
			Hits = number(data.Hits, 0),
			HitsNeeded = math.clamp(math.floor(number(data.HitsNeeded, rule.Hits)), 1, #ui.pips),
			Timeout = math.max(number(data.Timeout, FishingConfig.MinigameTimeout), 0.1),
		}
		setPhase("Reeling")
		minigame = mg
		minigameStart = os.clock()
		lastTap = -math.huge
		tapNeedle, tapZone = nil, nil
		showMinigame(mg)
	end

	local function onZone(data: { [string]: any })
		local mg = minigame
		if phase ~= "Reeling" or not mg then
			return
		end
		local oldCenter = mg.ZoneCenter
		mg.ZoneCenter = number(data.ZoneCenter, mg.ZoneCenter)
		mg.Hits = number(data.Hits, mg.Hits + 1)
		local predicted = predictedHit == mg.Hits -- удар уже сыгран по нажатию
		predictedHit = nil
		refreshPips(mg)
		-- Зона прыгает сразу (без скольжения): где она нарисована, там её и проверяет сервер.
		ui.zone.Position = UDim2.fromScale(mg.ZoneCenter, 0.5)
		celebrateHit(mg, oldCenter, predicted)
	end

	-- Конец рыбалки по слову сервера: его CastCooldown пошёл сейчас — и наш отсчёт заново
	-- (если леску сматывал сам игрок, сервер узнал об этом позже клиента).
	local function endSessionByServer()
		endSession()
		startCastCooldown()
		refreshButtons()
	end

	-- Поймал: мини-игра «побеждает», потом прыжок рыбы и карточка (beginCatch). Счётчик улова
	-- ведёт HudController; пока 🐟 не прилетела, он держит прошлое число (CounterHold).
	local function onCaught(data: { [string]: any })
		local fish = parseFish(data.Fish)
		if fish then
			winGhost(fish.Rarity)
		end
		if fish then
			catchScreen = true -- кнопка сразу «замирает» (без промежуточного «ЖДЁМ…» с выскоком)
			-- Этап 3: что стало с рыбой в садке (штамп, «+$/с», куда полетит карточка).
			cardTank = if typeof(data.Tank) == "table" then data.Tank else nil
		end
		endSessionByServer()
		if fish then
			beginCatch(fish, number(data.Total, 0))
		end
	end

	local function onLost(data: { [string]: any })
		local reason = if typeof(data.Reason) == "string" then data.Reason else ""
		local ghost = phase == "Reeling" and ui.minigame.Visible
		if ghost then
			missGhost(if reason == "timeout" then "ВРЕМЯ!" else "МИМО!")
		end
		endSessionByServer()
		local text = if typeof(data.Text) == "string" and data.Text ~= "" then data.Text else LOST_TEXT[reason]
		if ghost then
			-- Подсказка — когда копия мини-игры уходит (они стоят в одной колонке и не спорят).
			hintHeldUntil = os.clock() + MISS_HOLD - 0.02
			ui.hint.Visible = false
			later(phaseTrove, MISS_HOLD, function()
				showHint(text or "Рыба ушла", "warning")
			end)
		else
			showHint(text or "Рыба ушла", "warning")
		end
	end

	local function onIdle(data: { [string]: any })
		endSessionByServer()
		local text = if typeof(data.Reason) == "string" then IDLE_TEXT[data.Reason] else nil
		if text then
			showHint(text, "info")
		end
	end

	local function onDenied(data: { [string]: any })
		if data.Reason == "busy" then
			syncFromAttribute() -- сервер считает, что леска уже в воде
		elseif phase == "Pending" then
			setPhase("Idle")
		end
		if typeof(data.Text) == "string" and data.Text ~= "" then
			showHint(data.Text, "warning")
			UiFx.wiggle(ui.actionButton, 7, 2, 0.3) -- «нет»
		end
	end

	local HANDLERS: { [string]: ({ [string]: any }) -> () } = {
		Waiting = onWaiting,
		Bite = onBite,
		Minigame = onMinigame,
		Zone = onZone,
		Caught = onCaught,
		Lost = onLost,
		Idle = onIdle,
		Denied = onDenied,
	}

	function onFishingState(state: any, data: any)
		local handler = if typeof(state) == "string" then HANDLERS[state] else nil
		if handler then
			handler(if typeof(data) == "table" then data else {})
		end
	end
end

--------------------------------------------------------------------------------
-- Удочка в руке и персонаж
--------------------------------------------------------------------------------

local function unequipRod()
	if not rod then
		return
	end
	rod = nil
	rodTrove:Clean()
	endSession() -- сервер сам смотает леску ("Idle" { Reason = "unequipped" })
end

local function equipRod(tool: Tool)
	if rod == tool then
		return
	end
	unequipRod()
	rod = tool
	rodTrove:Connect(tool.Activated, function()
		-- С тач-экрана Activated приходит и от движения камеры / джойстика. В мини-игре такое
		-- «нажатие» мимо зоны стоило бы рыбы, на экране улова — пропустило бы показ или закрыло
		-- карточку, пока игрок разглядывает рыбу над головой, с «КУДА ИДТИ?» — дёргало бы подсказку
		-- на каждом шаге к пирсу. Там считаются только кнопка (и карточка, и панель мини-игры).
		-- (Клик мышью по миру на ноутбуке с тач-экраном работает.)
		if
			(phase == "Reeling" or catchScreen or isFar())
			and UserInputService:GetLastInputType() == Enum.UserInputType.Touch
		then
			return
		end
		doAction(false)
	end)
	ContextActionService:BindAction(ACTION_NAME, onActionInput, false, Enum.KeyCode.F, Enum.KeyCode.ButtonR2)
	-- 1 — убрать удочку в рюкзак, как прежней панелью предметов (кнопка снова «ВЗЯТЬ»), но только
	-- в покое: заброс, поклёвку, мини-игру и экран улова клавиша не обрывает.
	ContextActionService:BindAction(STOW_ACTION, function(_name, state, _input): Enum.ContextActionResult
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if state ~= Enum.UserInputState.Begin or phase ~= "Idle" or catchScreen or not humanoid then
			return Enum.ContextActionResult.Pass
		end
		humanoid:UnequipTools()
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.One)
	rodTrove:Add(function()
		ContextActionService:UnbindAction(ACTION_NAME)
		ContextActionService:UnbindAction(STOW_ACTION)
	end)
	refreshButtons()
	refreshContextHint()
end

local function onCharacterAdded(character: Model)
	characterTrove:Clean()
	characterTrove:Add(unequipRod)
	characterTrove:Add(destroyGuide)
	local alive = true
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		characterTrove:Connect(humanoid.Died, function()
			alive = false
			unequipRod() -- мёртвым не рыбачат: кнопка прячется сразу, а не при возрождении
			refreshContextHint() -- (и «ВЗЯТЬ», если удочка была в рюкзаке)
		end)
	end
	characterTrove:Connect(character.ChildAdded, function(item: Instance)
		if alive and isRod(item) then
			equipRod(item :: Tool)
		end
	end)
	characterTrove:Connect(character.ChildRemoved, function(item: Instance)
		if item == rod then
			unequipRod()
		end
	end)
	-- Подсказки по месту и кнопка («ВЗЯТЬ» / «возьми удочку», «иди к кругу» + луч, «жми»).
	local sinceCheck = 0
	characterTrove:Connect(RunService.Heartbeat, function(dt: number)
		sinceCheck += dt
		if sinceCheck < CONTEXT_CHECK_INTERVAL then
			return
		end
		sinceCheck = 0
		refreshContextHint()
	end)
	endSession()
	for _, item in character:GetChildren() do
		if isRod(item) then
			equipRod(item :: Tool)
		end
	end
end

local function onCharacterRemoving()
	characterTrove:Clean()
	endSession()
end

--------------------------------------------------------------------------------
-- Запуск
--------------------------------------------------------------------------------

local function collectUi(hud: ScreenGui): Ui
	local fishing = child(hud, "Fishing")
	local area = child(fishing, "ActionArea")
	local action = child(area, "ActionButton")
	local alert = child(fishing, "BiteAlert")
	local mini = child(fishing, "Minigame")
	local title = child(mini, "Title")
	local track = child(mini, "Track")
	local zone = child(track, "Zone")
	local pipsFolder = child(mini, "Pips")
	local hint = child(fishing, "Hint")
	local card = child(fishing, "CatchCard")
	local banner = child(card, "Banner")
	local nameLabel = child(card, "NameLabel")
	local mutation = child(card, "MutationLabel")
	local info = child(card, "InfoLabel")
	local weight = child(info, "Weight")
	local price = child(info, "Price")
	local counter = child(child(hud, "RightButtons"), "TankButton")

	local pips: { Frame } = {}
	for index = 1, 5 do
		local pip = pipsFolder:FindFirstChild(`Pip{index}`)
		if not pip then
			break
		end
		table.insert(pips, pip :: Frame)
	end

	return {
		hud = hud,
		actionButton = action,
		actionIcon = child(action, "Icon"),
		actionCaption = child(action, "Caption"),
		actionRing = child(action, "Ring"),
		stopButton = child(area, "StopButton"),
		biteAlert = alert,
		biteLabel = child(alert, "Label"),
		biteTimer = child(alert, "Timer"),
		biteIcons = { child(alert, "IconLeft"), child(alert, "IconRight") },
		minigame = mini,
		title = title,
		titleFill = child(title, "TextFill"),
		pips = pips,
		track = track,
		zone = zone,
		zoneGlow = child(zone, "Glow"),
		zoneFlash = child(zone, "Flash"),
		needle = child(track, "Needle"),
		timeFill = child(child(mini, "TimeBar"), "Fill"),
		hint = hint,
		hintLabel = child(hint, "Label"),
		hintIcon = child(child(hint, "IconSocket"), "Icon"),
		dim = child(fishing, "CatchDim"),
		rays = child(fishing, "CatchRays"),
		card = card,
		banner = banner,
		bannerFill = child(child(banner, "Face"), "Fill"),
		rarityLabel = child(banner, "RarityLabel"),
		fishGlow = child(card, "FishGlow"),
		viewport = child(card, "Viewport"),
		newStamp = child(card, "NewStamp"),
		nameLabel = nameLabel,
		nameFill = child(nameLabel, "TextFill"),
		mutationLabel = mutation,
		mutationFill = child(child(mutation, "Face"), "Fill"),
		mutationIcon = child(mutation, "Icon"),
		mutationCaption = child(mutation, "Caption"),
		infoLabel = info,
		weightChip = weight,
		weightLabel = child(weight, "Label"),
		priceChip = price,
		priceIcon = child(price, "Icon"),
		priceLabel = child(price, "Label"),
		counter = counter,
		wallet = child(child(child(hud, "Status"), "Wallet"), "Money"),
		tankStamp = child(card, "TankStamp"),
		baseBanner = hud:FindFirstChild("BaseBanner") :: GuiObject?,

		-- Улов, UI v2 (FUI-01…12).
		fishing = fishing,
		status = child(hud, "Status"),
		tapHint = child(card, "TapHint"),
		cardOutline = child(card, "Lip"):FindFirstChildOfClass("UIStroke") :: UIStroke,
		priceMult = child(price, "Multiplier"),
		titleSlam = child(fishing, "TitleSlam"),
		titleLabel = child(child(fishing, "TitleSlam"), "Label"),
		titleSlamFill = child(child(child(fishing, "TitleSlam"), "Label"), "TextFill"),
		titleLetters = child(child(fishing, "TitleSlam"), "Letters"),
		dimBands = {
			child(child(fishing, "CatchDim"), "Top"),
			child(child(fishing, "CatchDim"), "Bottom"),
			child(child(fishing, "CatchDim"), "Left"),
			child(child(fishing, "CatchDim"), "Right"),
		},
		-- UI v2, игра:
		actionArea = area,
		actionOutline = child(child(action, "Icon"), "Outline"),
		actionFill = child(child(action, "Icon"), "TextFill"),
		actionBobber = child(action, "Bobber"),
		keyChip = child(action, "KeyChip"),
		keyLabel = child(child(action, "KeyChip"), "Key"),
		tapCue = child(action, "TapCue"),
		stopCaption = child(child(area, "StopButton"), "Caption"),
		aura = child(mini, "AuraStroke"),
		auraFill = child(child(mini, "AuraStroke"), "AuraFill"),
		rider = child(track, "Rider"),
		timeBar = child(mini, "TimeBar"),
		pipsFrame = pipsFolder,
		tapPad = child(mini, "TapPad"),
		biteTapPad = child(alert, "TapPad"),
		hintSocket = child(hint, "IconSocket"),
		pedestal = child(card, "Pedestal"),
		window = child(child(card, "Face"), "Window"),
	}
end

local function readDefaults(): Defaults
	local track = ui.track
	return {
		minigamePosition = ui.minigame.Position,
		biteTimerSize = ui.biteTimer.Size,
		biteTimerColor = ui.biteTimer.BackgroundColor3,
		zoneHeight = ui.zone.Size.Y.Scale,
		needleY = ui.needle.Position.Y.Scale,
		pipColor = if ui.pips[1] then ui.pips[1].BackgroundColor3 else Palette.Slate.Lip,
		hintPosition = ui.hint.Position,
		iconRotation = ui.actionIcon.Rotation,
		dimTransparency = ui.dim.BackgroundTransparency,
		trackLeft = track.Position.X.Scale - track.AnchorPoint.X * track.Size.X.Scale,
		trackWidth = track.Size.X.Scale,
		trackMidY = track.Position.Y.Scale + (0.5 - track.AnchorPoint.Y) * track.Size.Y.Scale,
		namePosition = ui.nameLabel.Position,
		mutationPosition = ui.mutationLabel.Position,
		-- UI v2, игра:
		alertPosition = ui.biteAlert.Position,
		hintSize = ui.hint.Size,
		riderY = ui.rider.Position.Y.Scale,
		glowSize = ui.zoneGlow.Size,
		timeBarSize = ui.timeBar.Size,
		bobberPosition = ui.actionBobber.Position,
		tapCuePosition = ui.tapCue.Position,
		stopPosition = ui.stopButton.Position,
		stopSize = ui.stopButton.Size,
		minigameSize = ui.minigame.Size,
		actionSize = ui.actionButton.Size,
		actionBuilt = ui.actionButton.Size,
		actionPosition = ui.actionButton.Position,
		captionSize = ui.actionCaption.Size,
		ribbonSize = (ui.actionButton:FindFirstChild("CaptionRibbon") :: GuiObject).Size,
	}
end

-- Клавиша действия на «клавише» у кнопки: есть клавиатура — F, геймпад — R2 (на телефоне — нет).
local function detectKeyHint(): string
	if UserInputService.KeyboardEnabled then
		return "F"
	elseif UserInputService.GamepadEnabled then
		return "R2"
	end
	return ""
end

-- Текущее состояние (для других контроллеров и тестов).
function FishingController.GetPhase(): string
	return phase
end

function FishingController:Start(hud: ScreenGui)
	ui = collectUi(hud)
	defaults = readDefaults()
	keyHint = detectKeyHint()

	ui.actionButton.Visible = false
	ui.stopButton.Visible = false
	ui.biteAlert.Visible = false
	ui.minigame.Visible = false
	ui.card.Visible = false
	ui.dim.Visible = false
	ui.rays.Visible = false
	ui.hint.Visible = false
	ui.tapPad.Visible = false
	ui.biteTapPad.Visible = false
	ui.tapCue.Visible = false
	ui.actionBobber.Visible = false
	ui.keyChip.Visible = false

	-- Оформление — под защитой: упади что-то из него в настоящем Roblox (API движка, загрузка
	-- помощника), кнопку действия всё равно подключим ниже — её показывает только опрос
	-- персонажа (onCharacterAdded). Ошибка — красным в Output (с путём), а не молча.
	local function guarded(what: string, fn: () -> ())
		local trace = ""
		local ok = xpcall(fn, function(message: any)
			trace = debug.traceback(tostring(message), 2)
		end)
		if not ok then
			task.spawn(error, `[FishingController] {what}: {trace}`, 0)
		end
	end

	-- Центральная колонка — между джойстиком и кнопкой действия (и при смене размера экрана).
	guarded("колонка", function()
		layoutColumn()
		hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if hud.AbsoluteSize ~= laidOutFor then
				layoutColumn()
			end
		end)
	end)

	-- Нажатие «сжимает» кнопки (связи живут, пока жив HUD — всю сессию).
	guarded("нажатие", function()
		UiFx.press(ui.actionButton, { sound = "click" })
		UiFx.press(ui.stopButton, { sound = "click" })
	end)

	-- Персонаж — сразу после разметки, до остального: опрос при нём (раз в CONTEXT_CHECK_INTERVAL
	-- с) — единственное, что показывает кнопку («ВЗЯТЬ» на базе сразу после появления). Ниже —
	-- ввод, ответы сервера и остальное оформление (тот же кадр: нажать раньше них нельзя).
	player.CharacterAdded:Connect(onCharacterAdded)
	player.CharacterRemoving:Connect(onCharacterRemoving)
	if player.Character then
		onCharacterAdded(player.Character)
	end
	refreshButtons()

	-- В мини-игре нажатие считается в момент касания (MouseButton1Down приходит и от касания
	-- пальцем), а не отпускания (Activated): стрелка за время касания успевает уехать.
	ui.actionButton.MouseButton1Down:Connect(function()
		whiteRings(0, true) -- рябь от каждого касания (не дотягивается до кнопки прыжка)
		if phase == "Reeling" then
			doAction(true)
		end
	end)
	ui.actionButton.Activated:Connect(function()
		if phase ~= "Reeling" then
			doAction(true)
		end
	end)
	ui.stopButton.Activated:Connect(requestStop)
	-- Тач-экран: касание панели мини-игры — то же, что касание «ЛОВИ!», касание плашки
	-- «КЛЮЁТ!» — то же, что «ПОДСЕЧЬ!» (кнопка отзывается).
	ui.tapPad.MouseButton1Down:Connect(function()
		if phase == "Reeling" then
			doAction(false)
		end
	end)
	ui.biteTapPad.MouseButton1Down:Connect(function()
		if phase == "Bite" then
			doAction(false)
		end
	end)
	ui.card.Activated:Connect(tryCloseCard)
	local stateEvents = 0 -- сколько событий FishingState пришло (подстраховка ниже ждёт «своё»)
	Net.Event("FishingState").OnClientEvent:Connect(function(state: any, data: any)
		stateEvents += 1
		onFishingState(state, data)
	end)

	-- Подстраховка: сервер закончил рыбалку, а ответ потерялся — не держим старое состояние. Сервер
	-- ставит атрибут "Idle" ДО события ("Caught" / "Lost" / "Idle" приходит следом, в том же
	-- пакете): ждём SAFETY_NET секунд, и только если события так и не было, заканчиваем сами — иначе
	-- копия мини-игры не сыграла бы «МИМО!» / «ПОЙМАНА!», а «замёрзшая» кнопка «выскакивала» бы.
	local SAFETY_NET = 0.5 -- меньше CastCooldown: новый заброс за это время невозможен
	player:GetAttributeChangedSignal("FishingState"):Connect(function()
		local state = player:GetAttribute("FishingState")
		if (state == nil or state == "Idle") and isLineOut() then
			local seen = stateEvents
			task.delay(SAFETY_NET, function()
				local now = player:GetAttribute("FishingState")
				if seen == stateEvents and (now == nil or now == "Idle") and isLineOut() then
					endSession()
				end
			end)
		end
	end)
	-- Улов (UI v2): своя рыба долетела до места над головой — сигнал FishingFxController
	-- (подписка заранее: без прыжка он приходит раньше "Caught"). Подпись «закрыть» — по
	-- устройству; карточка переставляется, если экран поменял размер.
	guarded("FishingFxController", function()
		local fx = require(child(script.Parent, "FishingFxController")) :: any
		fx.OwnFishLanded:Connect(onOwnFishLanded)
	end)
	ui.tapHint.Text = if UserInputService.TouchEnabled
		then "Тапни — забрать!"
		else "Жми — забрать!"
	ui.titleSlam.Visible = false
	ui.minigame:GetPropertyChangedSignal("Visible"):Connect(function()
		if ui.minigame.Visible then
			minigameShownAt = os.clock()
		end
	end)
	ui.fishing:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if ui.card.Visible then
			placeCard(cardReveal.Scale, nil, nil, cardReveal)
		end
	end)
end

return FishingController
