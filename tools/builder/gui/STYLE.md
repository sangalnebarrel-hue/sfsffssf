# UI & FX style guide — «Симулятор» (UI v5; world FX and the catch from v1–v4)

The user's briefs: «мега красивый интерфейс и мега красивые пёстрые анимации, чтобы все были в
шоке» (v1/v2), «текстурки типа лего» (v3 — for the MAP) and, for UI v5: «а зачем ты сделал
интерфейс с шипами какими то, просто сделай интерфейс супер мега крутой с анимациями» with a
screenshot of a popular Roblox simulator. So the **map keeps its LEGO studs, the interface has
none**: it is the juicy simulator look of that screenshot — chunky saturated gradient buttons
with a THICK outline in a dark shade of their own hue, bold white lettering with a dark outline,
outlined emoji icons, big italic numbers and huge outlined titles with no panel at all,
translucent dark "glass" pills, a red «!» badge on a corner — and a lot of motion (§2).

Everything here is built from plain GUI instances (Frame, TextLabel/TextButton, UICorner, UIStroke,
UIGradient, UIScale, ViewportFrame) and built-in particle/sound content — **no uploaded images or
asset ids** (we cannot upload). Emoji are our icons (in game they are flat Twemoji).

## 1. Look

**Sim buttons and plates** (`Theme.sim`, the anatomy in §6.2) — the reference's buttons:

- a **face** filled with a vertical gradient of the colour, `Top` (lighter) → `Bottom` (juicier),
  almost square corners (`UIConfig.Sim.Radius` 0.08 of the short side: the thick outline rounds
  them) — plates that are not buttons (the base badge, toasts, chips) use `PlateRadius` 0.3;
- a **thick outline** (`Lip`'s UIStroke) in the colour's `Lip` — a DARK SHADE OF THE SAME HUE
  (value ≈ 0.29: dark green round green, navy round blue, maroon round red), never black:
  `UIConfig.Sim.Stroke` 6 px at 720 (≈ 4 px on a 390 px phone); small parts `MinorStroke` 4;
- a thin **light rim** just inside the outline (`Face.Rim`, white at `RimAlpha` 0.5, 2 px) —
  the reference's bevel;
- a smooth face: no side band, nothing raised, no glint; optional `gloss` (a soft white top
  half) and `shadow` (a soft Ink copy a little lower) for hero widgets.

Round buttons (`round = true`: the action button, the red badge, the trophy chip) use the same
anatomy with a 0.5 corner. **Glass** (`Theme.glass`) is the reference's timer pill: the same tree
with a black face at `Palette.Glass.Alpha` 0.5, no outline, no rim — hints, the action button's
caption, grooves. `UiFx.setCandy` turns a root between the two looks at runtime (a bright token →
a solid plate, `Glass` → glass; a root built as glass — attribute `CandyHome = "glass"` — stays
glass in dark tokens, Night / Coal).

**Panel-less display.** Big numbers and words stand on the 3D world with no plate, like the
reference's «👟 10», «$0» and «Украдите яйцо!»: the Wallet (stage 3; it took the catch counter's
row) is an outlined 💵 tilted −8° and a big **italic** `MoneyText`-green number «$1 234»
(`Theme.stat`); the base banner's «ТВОЯ БАЗА / ЛАЗУРНАЯ!» is a huge title
(`Theme.title`: white → base colour TextFill, an 8 px Ink outline at 720 and a drop-shadow twin
`<Name>Shadow` a little lower). Every surface on screen is smooth.

**Colours** (`UIConfig.Palette`, sampled from the reference; controllers recolour with
`UiFx.setCandy(root, token)` — Top → Bottom gradient, Lip = the outline):

| token | colour | use | top | bottom | outline |
|---|---|---|---|---|---|
| `Leaf` | lime green | «ЛОВИ!», «ЗАБРАТЬ!», success | #8BFA0C | #3FFF03 | #0A4800 |
| `Sky` | cyan | «ЗАБРОСИТЬ», info | #25FCFF | #03C6FF | #180149 |
| `Berry` | red | «СМОТАТЬ», danger, «НОВИНКА!» | #FF5357 | #F8060B | #490100 |
| `Sun` | orange | «КЛЮЁТ!», «ПОДСЕЧЬ!», warning | #FDC073 | #F77718 | #490C00 |
| `Gold` | yellow | «ВЗЯТЬ», price, Legendary | #FFF06A | #FECE08 | #4B2000 |
| `Grape` | purple | «ДОМОЙ», Epic | #E08CFF | #A43BFF | #2C0057 |
| `Pink` | pink | base colour | #FF9AD5 | #FF3FA8 | #4A0029 |
| `Mint` | turquoise | base colour (Cyan) | #6CFFE0 | #12D6B0 | #003D33 |
| `Slate` | light grey | disabled / waiting, no base | #EEF1F4 | #AEB6BF | #252B33 |
| `Night` | dark navy | the minigame panel, Mythic toast | #4A4F6A | #23263A | #06070D |
| `Cream` | white | the catch card, the key chip | #FFFFFF | #DDE6F0 | #141A26 |
| `Pond` | muted teal | «ЖДИ КЛЁВА…» (nothing to press) | #A9E4EE | #58AFC4 | #0B3440 |
| `Water` | aqua | water | #6FF2FF | #13B8D6 | #003A4D |
| `Coal` | black chip | dark chips | #3C414D | #14171D | #000000 |
| `Guard` | royal blue | «ЗАЩИТА», «ЩИТ», the shield chip and dome card (stage 4) | #8FB4FF | #3D6BFF | #0A1A57 |
| `Glass` | dark glass | hints, captions, grooves | #0B0D14 at Alpha 0.5 | — | none |

Base colours: `UIConfig.BaseSwatches` (Red = Berry, Blue = Sky, Yellow = Gold, Purple = Grape,
Orange = Sun, Cyan = Mint, Pink = Pink, Green = emerald #5FF5A8 → #14C76E); any other colour goes
through `UIConfig.swatchFor(color)` (top = colour 30 % towards white, bottom = the hue at
saturation × 1.1 and value ≥ 0.9, outline = the hue at value 0.29; greys get a dark grey).
`UIConfig.BadgeRed` (#FF4A3D → #F00A00, outline #4A0000) is the «!» badge, `MoneyText` #1BFF00 the
money digits of stage 3, `BillboardYellow` / `BillboardGreen` the words over the world (UI v5,
like the reference's «МАГАЗИН СЛЕДОВ» / «БЕСПЛАТНО!»: the base signs' «СВОБОДНО!» and «ТВОЯ
БАЗА!» in green, the held fish's price in yellow; §3 «Words in the world»).

Rarity: Common light grey `#F4F7FA→#B8C2CC`, Rare blue `#5FD0FF→#1E7BFF`, Epic purple
`#E08CFF→#A43BFF`, Legendary yellow → orange `#FFF06A→#FF9A00`, Mythic = an **animated rainbow**
(UIGradient with 7 hue keypoints whose Offset/Rotation moves). Mutation badges: Gold (gold
gradient + sparkles), Neon (#6BFFF4→#00C8FF, glowing pulse), Rainbow (animated rainbow). The e2e
bot's filled pip colour `UIConfig.Fishing.PipDone` rgb(64, 200, 96) never changes.

**Text.** One family: **Montserrat Heavy** (900, `UIConfig.Font.Family` =
rbxasset://fonts/families/Montserrat.json — the reference's heavy geometric sans, with Cyrillic;
`Theme.FONT`, `UiFx` uses the same); **Montserrat Heavy Italic** (`Theme.FONT_ITALIC`,
`Italic = true`) for numbers, floats («+$4/с», «ОТЛИЧНО!»), cooldown digits, the Wallet and the
«САДОК» chip. Never
FredokaOne / LuckiestGuy / Bangers / DenkOne / TitilliumWeb: no Cyrillic. White with a dark Ink
outline (UIStroke "Outline", Contextual, round joins). **CAPS voice** for badges, buttons,
banners, chips and titles («ЛАЗУРНАЯ БАЗА», «ДОМОЙ», «ЗАБРОСИТЬ», «РЕДКАЯ»; Cyrillic capitals
through `TextUtil.upper` — `string.upper` knows only Latin); sentence case for hints, plain toasts
and «Тапни — забрать!». Outlines at 720 px (`UiFx.fitStrokes` scales them with the screen height:
shapes ×0.65 … ×`Fx.StrokeMax` 1.2, text ×0.65 … ×`Fx.TextStrokeMax` 1.0, text never under
`Fx.TextStrokeMin` = 2 px):

| what | outline at 720 | on a 390-px phone |
|---|---|---|
| Small / Body tier | 2.5 | 2 |
| Button tier | 3 | 2 |
| Title tier | 3.5 | 2.3 |
| display text (the Wallet's money, cooldown digits, the price, floats) | 4.5 | 2.9 |
| huge titles (the base banner name, the rarity title) | 8 | 5.2 |
| emoji icons (the Ink contour round the emoji's shape) | 3 | 2 |
| shapes: buttons and plates | 6 | 3.9 |
| small parts (the badge disc, chips, the trophy chip's tip) | 3–4 | 2–2.6 |

A tiered label gets at least its tier's outline (`Theme.label`); dark text on a white chip (the
key chip, the weight chip, «Тапни — забрать!») goes without (`Outline = false` /
`TextStrokeTransparency = 1`). Never below 12 px on a phone (UITextSizeConstraint).

**Type scale.** Text that means the same thing has the same size on one screen. Four tiers
(`UIConfig.Type`, Roblox TextSize = line height in px on a 390 px tall screen; Montserrat is wider
than the old Nunito, so the numbers are a little smaller for the same cap height):

| tier | px | used for |
|---|---|---|
| `Title` | 20 | base badge, minigame title, rarity banner, fish name |
| `Button` | 17 | action caption, «СМОТАТЬ», the base banner's caption, Legendary/Mythic broadcasts |
| `Body` | 15 | hints, Help, toasts, «Тапни — забрать!» |
| `Small` | 14 | «ДОМОЙ», chips (weight), the broadcast's «who» line |

A label gets its tier with `Theme.label(…, { Tier = "Body" })` (attribute `TextTier`);
`UiFx.fitText(hud)` (HudController) sets Max = tier × clamp(H / 390, 1, 1.6), Min = Max − 2 for
every tiered label, also ones cloned later. Give the box at least that height; long copy is
shortened (or the widget grows a line), never shrunk below its tier. Display text (the giant
rarity title, the base banner name, cooldown digits, the Wallet's money, the catch card's
price) is box-driven, not tiered. CAPS Cyrillic is 10–20 % wider: check «ФИОЛЕТОВАЯ БАЗА»,
«ЗАБРОСИТЬ», «МИФИЧЕСКАЯ» on `phone_small`.

**Icons.** Emoji in their own TextLabel with a **dark Ink contour** round the emoji's shape
(`Theme.icon`, `Outline` 3 px at 720 — the reference's black-outlined icons; a faint glyph gets
none), upright (Rotation 0; only the Wallet's 💵 −8°, the base flag ±8°, stamps — «НОВИНКА!», a
mutation, «В САДОК!» — tilt). An icon may **overhang** its plate's left end (`Theme.plate` → `Icon`, or
`Socket = true` → a transparent holder "IconSocket" with the Icon in it: toasts, the base flag,
hints). 🎣 🐟 🏠 💰 ⭐ ✨ ❗ 💪 🔥 🌈 👑 🚩. The red **«!» badge** (`Theme.badge`) sits on a button's
top-right corner (Home has one, hidden until the shop of stage 5 lights it; «САДОК» lights its own
after the first fish ever, until the tank panel first opens).

**Hierarchy.** One idle accent per screen: only the action button idles (its shine sweep); the chrome
stays calm (the badge flashes its rim only when the base arrives, Home when its cooldown ends);
the Wallet's money is the biggest text of the chrome (its 1 Hz income tick is plain text: no
count-up, no bump). **Chrome micro-life** at most once per
8–12 s, one widget at a time and only in calm moments (not fishing, no catch, no toast, 6 s after
the last HUD event): the badge's flag waves, «САДОК»'s 🐠 wiggles, Home's 🏠 hops (HudController:
one task.delay chain, no connection, no frame work).

## 2. Motion (the "juice")

All motion comes from the client library `ReplicatedStorage.Shared.UiFx` (one place, consistent
timing); the default numbers live in `UIConfig.Motion`. Every effect must clean itself up (Destroy
temporary instances, cancel tweens) and accept a Trove or return a cleanup function.

| effect | how | timing |
|---|---|---|
| press | squash UIScale 1 → 0.9 and the face darkens a step (its white background under the gradient → 0.8 grey: the whole gradient darkens, the outline stays); on release an overshoot to 1.08 — capped at `Press.MaxGrow` 3 px of growth, so a big button never touches the Jump button — then a Back-Out spring to 1, the face brightens, the icon gets a **kick** (1.18 → 1 and −8° → rest, Back Out); a click at a random pitch 0.95–1.08; with a mouse also **hover** (1.05 while over) | 0.06 / 0.09 + 0.22 s |
| pop-in | UIScale 0 → 1 (Back Out), optional rotation −6° → 0; `staggerPop` pops a list one after another | 0.3 s, 0.05 s apart |
| pop-out | a short swell 1 → 1.06, then → 0 (Back In), hide or destroy | 0.16–0.2 s |
| punch | a felt two-step overshoot from → 1.1 (Quad Out) → 1 (Back Out): look changes, the badge appearing, arrivals | 0.09 + 0.22 s |
| snap-in | a panel drops from 8 px above (Quad In), squashes 1.08 × 0.92 on contact and springs back (Back Out), a tick (the minigame plate) | 0.12 + 0.18 s |
| rim flash | the face's light rim flashes solid white and fades back to `RimAlpha`, a white overlay 0.6 → 1 on the face, a breath 1 → 1.06 → 1 (`rimFlash`: the bite alert, «СМОТАТЬ», the minigame plate, the card's pedestal / banner / price, the badge on arrival, broadcast toasts) | 0.3 s |
| morph flash | an important look change (ПОДСЕЧЬ! / ЛОВИ! / ЗАБРАТЬ!): a white overlay on the face 0.4 → 1 and the icon pops 0.6 → 1.15 → 1 | 0.2 / 0.32 s |
| recolour | a copy of the face's OLD gradient covers it and fades while the new colours are already under it; the outline tweens to its new colour | 0.16 s |
| breathe | a primary button's idle life (ВЗЯТЬ / ЗАБРОСИТЬ / ЗАБРАТЬ!: 1.05 every 1.4 s, at most 4 px a side — the disc is anchored at its centre): one slow breath 1 → peak → 1 every period, only when visible, not pressed, not punched | 1.8 s period |
| shine | a white diagonal band (Transparency 1 → 0.25 → 1) sweeping Offset −1 → 1 across a button / plate | 0.6 s, every 3.5 s on the idle primary button |
| bob | an icon hops by 8 % of its height through its AnchorPoint (Quad Out up, Bounce Out down) — position and scale stay free for other effects | 0.18 + 0.32 s, every 2.2–3.0 s |
| sway | a slow ±1.5° rotation loop (the waiting plate «ЖДИ КЛЁВА…») | 2.4 s period |
| badge wobble | the red «!» pops in (punch 0 → 1.25 → 1, a white ring, a high tick), then every 2.8–3.6 s wiggles ±12° with a 1.12 bump; `badgeHide` swells and shrinks it away | 0.5 s per wobble |
| number roll | the «САДОК» chip «3/6 → 4/6» («slot machine»): the old number slides up and fades (Quad In), the new one rises from below (Back Out); the digits flash a colour (`flashText`, ≥ 0.34 s apart), the button bumps (1.3; 1.45 in the rarity colours for a fish from the card) and its 🐠 squashes (Elastic) | 0.16 / 0.24 s |
| count-up | a number ticks from → to (Quad Out); each new number bumps 1.06 → 1 (≤ 12 Hz: the catch card's price) | 0.6–1.0 s |
| ring timer | a ring round a button drains clockwise from 12 o'clock (two clipped halves, a rotating transparency gradient), colour full → middle over the first half, then middle → empty (one stage after the other, like the bar; `UIConfig.Fishing.TimeBar`; «ПОДСЕЧЬ!» uses the bite bar's green → yellow `Gold.Top` → red) | the duration, tweens + one `task.delay` |
| fly-up | icons fly on an arc from one widget into another (the card → «САДОК»; a sale's 💵 → `Wallet.Money`): with `count` > 1 they first scatter 40–70 px out of the source, then fly one by one 0.05 s apart (Common 1, Rare 2, Epic 3, Legendary 4, Mythic 6 — `Motion.Fly.Count`; 💵 3–8 by the amount, `UIConfig.Wallet.Coins`), `onEach` ticks per icon | 0.18 + 0.45–0.6 s |
| slam | UIScale 2.2 → 1 (Back Out) + small shake (the base banner's name) | 0.35 s |
| stamp | 3 → 1 with a −16° turn («НОВИНКА!», a mutation) | 0.3 s |
| pulse | UIScale 1 ↔ 1.08 (Sine InOut, repeat) | 0.8 s period |
| wiggle | Rotation ±6° (Sine, 3 swings) | 0.4 s |
| shake | Position jitter ±1.5 % decaying | 0.25 s |
| glow ring | a copy of the round shape behind it, scale 1 → 1.5, transparency 0.3 → 1 | 0.6 s, repeat while important; stop fades live rings in 0.1 s |
| rays | sunburst of 8–16 thin rotated bars in alternating rarity colours, growing from the centre (Quad Out), slowly rotating (≈20°/s; two rings turn opposite ways), behind titles and the catch card; on touch: no halo quads, no breathing, size capped (`maxPx`); `settle()` after the reveal; with a `hole` the middle stays empty | while shown |
| confetti | 30–60 small Frames (squares/strips, vivid colours, rotation), launched up/out then falling with gravity and spin, fading in the last 30 % | 1.6–2.2 s |
| sparkles | ✨ / ⭐ labels popping in/out at random spots around an element (on a text plate only beside it, never on its letters) | while shown |
| float text | «ОТЛИЧНО!», «+1 🐟», «МИМО!» in Montserrat Heavy **Italic** with a 4 px outline: pop, rise 8 % and fade, slight rotation | 0.8 s |
| rainbow | UIGradient colour keypoints shifted every frame (hue cycle), or Rotation spin | continuous while shown |
| flash | full-screen white / rarity-coloured Frame 0.6 → 1 transparency (`flashBig` exists but is not used: never a near-solid screen on a catch landing) | 0.25 s; ≤ 3 per second |
| shockwave | the landing hit at a point: a thick rarity ring + a thin white one expand from it, a soft disc fades faster; the middle stays clear | 0.45 s |
| edge vignette | 4 edge bands in a colour (or a gradient), fading towards the centre; static, pulsing (≥ 0.34 s period) or one-shot | tension, bite, perfect hit |
| FOV punch | the camera zooms in a few degrees and back (all punches summed, capped at −8°); with `easeIn` a slow wind-up | 0.08 s in, 0.35 s out |
| sounds | pooled built-in sounds with a pitch; rarity arpeggio (Common 1 note … Legendary 4, Mythic 7) | events |

Easing defaults: Back Out for appearing, Quad In for leaving, Sine for loops. Nothing linear
except timers. Stagger groups by 0.03–0.06 s. A label's drop-shadow twin (`<Name>Shadow`) moves
with it: `setText`, `popIn`, `bump`, `slam`, `punch` and `shake` drive both.

**Idle budget.** Everything that lives while nothing happens — breathe, shine loops, bob, sway, the
badge wobble, the chrome micro-life, glow-ring loops — runs on **tweens and `task.delay` chains
only** (no RenderStepped / Heartbeat connection, no per-frame work); a chain ends by itself when
its widget is hidden or destroyed. Frame effects (`UiFx.schedule`: confetti, burst, countUp,
rainbow, timerBar, flyTo, trail) are for events and stop by themselves or through their stop
function; with nothing running the shared frame connection is gone (`UiFx.activeJobs() == 0`).

**Reduced motion** (`UiFx.reducedMotion()`: Roblox's ReducedMotionEnabled when the client has it,
or `UiFx.setReducedMotion(true)`), handled in UiFx in one place: no overshoots (pops become a short
Quad Out from 0.9), no wobble / bob / sway / breathe, no shake, no text flashes, half the confetti,
a slower rainbow (`Motion.Reduced`). Nothing ever flashes faster than 3 times per second.

## 3. Where it is used

- **HUD chrome** (tools/builder/gui/Hud.luau, HudController, NotifyController — the reference
  implementation of §1): the base badge (a sim plate in the base swatch — gradient, thick outline
  in the dark shade of the base colour — with an outlined 🚩 overhanging its left end, tilted 8°,
  «ЛАЗУРНАЯ БАЗА» in CAPS at the Title tier; «ИЩЕМ БАЗУ…» / «ЖДЁМ БАЗУ…» on light grey; it bumps
  and flashes its rim only when the base arrives); the base banner (first assignment: NO panel — a
  huge outlined title like the reference's «Украдите яйцо!»: the caption «ТВОЯ БАЗА» over the name
  «ЛАЗУРНАЯ!» in white → base colour with an 8 px Ink outline and a drop-shadow twin, the 🚩
  waving beside it; the name slams in from its baseline (anchored at its bottom middle: it grows up
  and sideways, never down) no bigger than the room — it keeps 16 px to the shown status rows, the
  right column and the action disc's place even at the start of the slam, and where «ВЗЯТЬ» stands
  under the name's end (phones; the small 667 px phone at rest) the banner is lifted until the name
  clears the disc by 16 px, never closer than 16 px to the status rows (HudController placeBanner /
  nameSlamFrom, V-02) — and flashes, rays, confetti, a fanfare; after 2 s it shrinks
  into the badge, which bumps and flashes its rim); the Wallet and «САДОК» (stage 3, see «The
  Wallet and «САДОК»» below: the catch counter is gone); the Home button (a
  square purple Grape sim button, a big outlined 🏠 and «ДОМОЙ» ON its bottom edge, the red «!»
  badge on its top-right corner — hidden until the shop of stage 5; the press squashes it, kicks
  the 🏠; cooldown: a dark veil drains down, big italic digits in the middle — the last 3 s
  flash orange —, the house fades, «ЖДИ» punches in over the veil; ready: a punch, a rim flash, a
  purple ring, one shine, «ДОМОЙ» punches back in its clipped caption band; a press during the
  cooldown shakes it «no»; the first base pops the button in on its own spot (scale 0.3 → 1, Back
  Out — never the column's Position: the fishing layout reads it) and spins the 🏠 in); toasts
  (sim plates by kind — Sky info, Leaf success, Sun warning, Berry danger, the base colour for the
  base — with the outlined icon overhanging the left end; slide-down + bounce and a 0.5 → 1 pop,
  the icon spins in (−180° → 0, Back Out) once the plate has landed — warning and big news: then
  the emoji wiggles —, a shine; leaving: up 20 px, +4°, fading; the others slide to their slots
  with a little overshoot (Back Out); a column right under the status stack — 3 on a PC (clear of
  the chat window), 1 on a tablet or a phone (above the avatar's head); none while the catch is on
  screen, 1 over the bite / minigame (on phones none but danger), none but danger while a hit word
  or a minigame ghost («МИМО!», «ПОЙМАНА!») rises into the column, the rest queue — a toast pushed
  off in the first half of its life comes back); Legendary (a yellow Gold plate, 🌟) and Mythic (a
  dark Night plate in a spinning rainbow OUTLINE, 🌈 — the rainbow only on the outline, never
  behind the letters) broadcasts are bigger plates that punch in (0.3 → 1.12 → 1) and land with a
  ring in the rarity colour, a rim flash and a gold flash of the headline (sparkles 0.3 of its
  height pop only beside the plate — none on «×5!», r4 ART-02), in two lines — who
  (Small, never under 14 px) over what (up to Title, the rarity word in capitals), never wider than
  the column — 1.25 columns on a touch screen, centred, clear of Home — (measured per glyph,
  `UiFx.textWidth`; on a touch screen a long headline first shrinks, down to 12 px, and wraps into
  two Body lines only when even that does not fit: on the smallest phone the plate stays one line
  tall, over the avatar's head, not on it); someone else's
  catch never washes the screen (no edge pulse); on
  phones they wait while the own trophy is held over the head; leaving: rise + fade, ≥ 0.7 s
  apart).
  Someone else's Legendary / Mythic pillar off-screen (behind the camera or past the frame's
  edge): a small chip at that screen edge (HUD.TrophyPointer → «TrophyChip», ≈ 46 px, y 0.38 of
  the HUD, ≥ 16 px from the edge) — an outlined 🌟 / 🌈 on a round yellow / rainbow sim disc ringed
  in the catcher's base colour, its tip nudging 6 px towards the edge — for the pillar's life;
  gone while the pillar is on screen; on phones hidden during the own bite / minigame / catch (the
  toast rule). Only the primary CTA idles (breath, shine, icon wiggle, the newcomer's «!»); the chrome stays calm.
- **Fishing UI** (tools/builder/gui/Fishing.luau, FishingController). The playing widgets are built
  with the sim API itself (`simButton`, `sim`, `glass`, `plate`, `socket`, `badge` — the catch card
  too): the action button is the star — a big ROUND sim button
  (`simButton` "round": the chunky `Sim.Stroke` outline in the dark shade of its hue, the light rim,
  a gloss over its upper half) with an outlined emoji in the middle and its caption on a glass
  stadium across its bottom (ActionArea, 0.66 of the HUD height, max 320 x 240). It is anchored at
  its CENTRE (placed in px by FishingController: its left edge 2 px left of the area), so every
  scale effect grows it evenly round its middle; how far it may grow on this screen and still keep
  16 px (its outline included) to the Roblox Jump button is its attribute `GrowMax` (the bite's
  pulse and a hit's bump are capped by it), and its white glow rings (a tap's ripple included) keep
  16 px to Jump at that peak too (`FishingLayout.RING`): where they would not fit — a 4:3 tablet,
  whose Jump button is bigger and higher — the disc is drawn smaller (`FishingLayout.discFit`,
  ≈ 0.9, its left edge and bottom kept: the hint column and the catch card are on its left). At rest ВЗЯТЬ / ЗАБРОСИТЬ breathe (1.05 every 1.4 s, ≤ 4 px a side), shine and
  wiggle their icon with a little bump every 2.8–3.6 s, and until the session's first cast a red «!»
  badge wobbles on the disc's upper left shoulder (the key chip has the right one); ЗАБРАТЬ! breathes
  with its rings; the waiting plate sways ±1.5°. Every look change on screen: the colours and the
  outline cross-fade (`UiFx.recolor`), the disc punches (0.86 → 1.08 → 1), the icon spins in
  (−120°, 0.2 → 1), the new caption punches in place (no slot roll on the narrow pill); ПОДСЕЧЬ! /
  ЛОВИ! / ЗАБРАТЬ! add the white «transform» flash and a swoosh. The disc's colour, icon and caption
  change by state (ЗАБРОСИТЬ 🎣 → ЖДИ КЛЁВА… — v3 UIM-09: a muted Pond plate 15 % smaller round its
  middle (its caption pill keeps its width, the caption may drop to the Small tier to stay on one
  line), no rings (nothing to press), a bobbing float and 1–2 nibbles «?», the first wait of the
  session explains itself with a hint «Жди, пока клюнет — потом жми!» →
  ПОДСЕЧЬ! «!» → ЛОВИ! 🎯; Slate ⏳ while waiting on the server, КУДА ИДТИ? 🧭 far from the spot — it
  shows the way, never scolds: a calm 💡 hint, the compass turns, the guide beam flares; ВЗЯТЬ
  in gold with white rings WHEREVER the rod is in the Backpack (a base, alive, not fishing — the
  screen never offers only «ДОМОЙ»: just spawned at the base, after a respawn, after «ДОМОЙ»); far
  from the spot the guide beam and the «where to go» hint come with it, taken there it morphs into
  КУДА ИДТИ?; keys 1 / F / R2 take the rod while it shows (like the old hotbar; never E, the
  ProximityPrompt key), 1 puts it away at rest; a dim frozen ЖДЁМ… during the catch until the card is fully shown, then
  ЗАБРАТЬ! 👍 in Leaf with white rings — it closes the card), glow rings while it matters, a sim
  press (squash, a darker face, an overshoot, the icon kicks), ripple on tap; a white key chip («F»
  / «R2», a Cream sim chip with the minor outline) on its shoulder without touch (ВЗЯТЬ too; not
  КУДА ИДТИ?, whose key casts nothing), punching in when it appears. «СМОТАТЬ» (≥ 44 px, ≥ 22 px above the circle) only while waiting: a red `simButton`
  "row" — the outlined 🎣 («reel the rod in») at its left end, the caption filling the rest, like
  the reference's «Магазин» — anchored at its bottom-RIGHT corner, so its pop-in (0.2 → 1, the 🎣
  spinning in −180°, the caption punching, the rim flashing) grows away from the Home column: it
  keeps 16 px to it at rest and on the way in (FishingController narrows it from the right and, on
  a tablet, lifts it clear of the higher Jump button); it swells and pops out once a fish bites.
  Bite alert (an orange Sun sim plate with the chunky outline, its rim flashes as it lands): a
  huge «КЛЮЁТ!» — white → gold display text, a thick Ink outline and the reference title's
  drop-shadow twin — jumps out of the own bobber (0.35 → 1,
  flying to its slot; where that path would cross the fisher it pops up in place — v3: never a
  screen-wide slam over the fisher; with no bobber on screen a phone pops it up in place, a tablet
  or a PC slams it from above, no bigger than the room — the plate and its outline keep 16 px to
  «ПОДСЕЧЬ!»'s ribbon at the peak of its punch, the thumbstick and the fisher, else it pops up in
  place too: FishingController slamRoom, V-03) with a sun flash and a FOV punch; the word punches in after the
  plate, the two «!» glyphs (level with the word) pop in one after the other, turning (their text
  boxes stay within the plate's bottom outline, tilted, wiggling or popping: 0.8 of its height); sun edge glow, one BITE_BEAT for
  the plate, the button and the swinging «!» glyphs, the word flashing gold on the beat (≤ 3/s), a
  shake every other beat once the window hurries; the countdown is a gradient bar in a glass groove
  (green → yellow → red: `Leaf.Top` → `Gold.Top` — a real yellow, not Sun's peach top on the
  orange plate — → `Berry.Bottom`) AND a ring timer in the same colours, stage after stage (r3,
  SIMB-C2-01: a delayed second colour tween cancelled the first one, so the ring went green →
  red through olive), draining clockwise from 12 o'clock INSIDE the «ПОДСЕЧЬ!» disc,
  right along its dark outline (over the face, under the caption pill, on a dark track that shows
  the time gone; no room outside it — 16 px to Jump: `UiFx.ringTimer` with pad 0, z and track, its
  strokes drawn inward so the halves' clip never cuts them; tweens only; the hook removes it). The
  plate leaves as a ghost (FxBiteOut): hooked — it swells and pops away (0.14 s) with a white ring
  UNDER the minigame that takes its slot; too late — it drifts down 10 px and fades. On touch the
  plate is a tap pad, a 👇 hanging over the disc's top, a little left of the middle (tilted towards
  the centre, its fingertip on the outline, tapping down onto it: the icon and the caption stay
  clean, its box within the disc's width; not when the key chip shows the key) helps the first two bites, and
  the plate gets a little lower (or moves aside) when it would hide the own diving
  bobber or the own fisher (on a phone it stands under his feet; when the fishing camera lowers him
  to the very bottom of the frame — left of him, where the minigame comes next). Minigame (a dark
  navy Night sim plate with the chunky outline and a soft rim; it snaps on, its rim flashes and its
  title punches): a glass groove (darker than the bite's), the zone a green Leaf sim pill with the
  minor outline and a rider by rarity standing on its top edge (🐟 🐠 🐡 🦈 🐉) in the band
  between the title and the groove (0.74 of the track tall; r3, SIMB-C2-03: Legendary+ 1.16× on a
  breathing light disc in the rarity colour — the dark 🦈 reads on the navy panel — with thin
  rings in the same band, never across the title's letters) on a soft glow halo (bright at the
  zone, fading away from it; it breathes in height only), needle ▼ (a white pill with an Ink
  outline) with a bright speed streak of four ghost copies close together (white with a cyan tint
  `UIConfig.Fishing.NeedleGhost`, 0.2 → 0.75 transparent, narrower and shorter than the needle,
  no outline — r3, SIMB-C2-04: one streak, not dull teal slabs or extra needles; under the zone), the time bar in a glass groove, pips as round chips with the minor
  outline, an italic help line, a
  light Rare rim, Epic+ aura in the rarity colours (Legendary a gold sweep, Mythic a rainbow) —
  a band OUTSIDE the dark outline (`AuraStroke`, `Sim.Stroke` + 4 at 720: ≥ 2.5 px on phones;
  as wide as the outline it would hide under it), Legendary/Mythic slam the giant rarity
  word over the panel once (the first hit / miss / win word knocks it away: it swells and fades in
  0.12 s — never two words stacked; on phones it never climbs onto the base badge or the flag
  hanging over its left end — its −4° tilt counted, r4 ART-04: lower, over the panel's top edge,
  and smaller); the Mythic title's rainbow (red … cyan, no dark blue / purple) runs there and back
  (`UiFx.rainbow` `bounce`, r4 ART-01: as a circle cyan blended into red through grey); on a
  tablet or a PC the panel rests centred in the column, which keeps
  room for the aura band plus `MINI_JUICE` 5 % of its width a side (its pop-in overshoot, the
  snap-in squash 1.08 and the 1.06 hit bump), so even at that peak it stays ≥ 16 px from the
  action button's caption pill and the thumbstick (FishingController.layoutColumn, r3,
  SIMB-C2-02) — unless it would lie on the own fisher there (the fishing camera lowers him to the
  bottom of the frame: his legs, the brace), then it slides aside at the bottom or docks LEFT of
  him like on a phone, smaller as a whole (r4 UX-01, `MINI_DOCK_MIN` 0.75 under him, ≥ 208 px
  wide beside him; its real rarity aura kept 16 px off the thumbstick); on phones (HUD under 500 px)
  the panel always docks LEFT of the own
  fisher (FishingLayout: under the status stack, over the thumbstick, ≥ 208 px wide) — the whole
  fight (the brace, the crank, the bent rod) and the bobber stay in view; the words over the
  panel (the rarity word, the hit words even at their 1.3 pop, «МИМО!» / «ВРЕМЯ!») keep 8 px off
  the own fisher — moved aside, the rarity word narrower if it must — and off the status plates
  and the flag (`FishingLayout.clearOf`: they rise less; touching even at rest — a step aside of
  at most half the word, else lower), and a slam from big (the rarity word
  2.2, «ИДЕАЛЬНО!» 2) grows from its far edge when from its middle it would cross him
  (`FishingLayout.slamPivot`, r4 ART-03); the hit is shown at once (the needle freezes gold, sparks, rising pitch) with
  «ОТЛИЧНО!» → «СУПЕР!» → «МЕГА!» or «ИДЕАЛЬНО!» (within 25 % of the zone centre; the title flashes
  gold), pip turns into a
  ⭐; on touch the panel itself is a tap pad and the 👇 cue helps the first games; on miss / timeout a
  copy (FxMinigameMiss) blushes (its zone cross-fades to red, its green glow fades), shakes and says
  «МИМО!» / «ВРЕМЯ!»,
  and is gone before the reason hint springs up. Hint: the reference's timer pill — dark glass
  (`Theme.glass`, a stadium) with ITALIC white text (a warning / danger: a solid orange / red sim
  plate with the chunky outline, `UiFx.setCandy`) and the outlined 💡 / ⚠️ / 🚨 overhanging its left
  end, as wide as its text (`FishingLayout.hintWidth`, the text measured per glyph with
  `UiFx.textWidth`; at least 5 × its height); too long for one line in the column's room, it takes
  two EVEN lines like the reference's «через 54 / секунд» pill (the narrowest width for the best
  word break — no lone «жми!» on line 2, a dash never starts it), at the bottom centre
  under the fisher's feet (on a phone beside him when it would lie on his feet — and its entrance
  ends THERE: it rises a few px to the place `renderHint` chose, never back to the default spot on
  his feet; v3: no Roblox hotbar — the Backpack CoreGui is off, a custom hotbar comes with the shop
  stage), pops up from a few px below; an info 💡 hops twice. A text change of the same kind while
  it is up morphs the pill to its new width and place (0.2 s; growing, the old text stays until it
  is wide enough; shrinking, the new shorter text is on at once), the text punches and the 💡 hops —
  no new pop and no slot roll (two texts rolling in the narrowed pill spilled out of it); leaving, it
  swells and shrinks away (0.16 s; at once when the bite / the minigame take the column). Info
  hints (💡) leave after 4 s; «where
  to go» (far from the spot with the rod in hand OR in the Backpack — right after the spawn too,
  with the guide beam) comes back every 10 s while it still applies — it never retires before the
  player has reached the circle; a hint whose action the player has done
  twice (cast, took the rod, reached the spot) is not shown again (WOW-6); a hint about the place
  waits while the «ТВОЯ БАЗА» banner holds the middle of the screen (joining: the first «where to
  go» pops once the banner has landed in the badge, for its full 4 s), and on phones while the own
  trophy is held over the head (the trophy camera lowers him onto it) — the guide beam, a world
  object that covers no widget, does not wait. «ЗАБРОСИТЬ» shows 2 studs inside the server's
  SpotRadius (the server judges a lagging copy of the character). The catch (UI v2) shows the world
  first: the winning tap freezes the needle gold where it was tapped (gold zone flash, a glow ring, a
  small bump, a higher pop) until the server answers (≤ 1.5 s); on "Caught" the minigame plays its
  win (FxMinigameWin: ⭐, gold zone, the needle where it was tapped, sparks) and sinks away early, and
  «ПОЙМАНА!» slams in (2.4 → 1, tilted, ≈ 0.17 of the HUD height, in the rarity colours — Mythic a
  sweeping rainbow — with a glow ring) left of the character, never over the leap: in its band it
  keeps 8 px off the own fisher and 16 px off the thumbstick and the buttons (`sideLimits`; in a
  tight band it gets shorter, ≥ `CLIMAX.WinLeast` 40 px), its slam grows from the edge away from
  them (`FishingLayout.slamPivot`: right of the word stands the fisher — it grows leftwards, off
  the screen edge if need be) and its glow ring stops short of them (r4 UX-02 / UX-03), and is gone
  ≈ 0.2 s before the landing (a quiet beat before the shockwave); the status badge and the Wallet
  fade out, the button freezes; Epic+ get a narrow edge frame (0.13 of the height) that builds
  0.85 → 0.5 alpha into the landing (Quad In) and cuts off on it — Mythic's is a light rainbow
  cycling around the frame —, Legendary/Mythic an accelerating heartbeat (sound only) and a slight
  FOV wind-up while the fish leaps. On the landing (`FishingFxController.OwnFishLanded`) **a crisp
  burst at the fish, never a wash** (v3): a thin shockwave ring (`UiFx.shockwave`, `CLIMAX.Shock`:
  no glowing middle, ≈ 0.34 s; it starts outside the trophy — `from`, `CatchFx.clearRadius` —, so
  a giant fish on the smallest phone is not crossed by it) and sparks from the fish's point — no
  edge flash —, in the world a
  small white pop, a star of thin rarity rays and a thin halo at the fish (the own Legendary/Mythic
  pillar only rises 0.3 s later, with a thin core), shake and FOV punch, confetti; for Epic+ the
  rarity rays start around the fish (empty middle; during the title stage thin spokes, more
  transparent than the card's — `CLIMAX.TitleRays` — so no yellow/white glow piles up around the
  fish — v5: the empty middle is at least the trophy, `CatchFx.clearRadius`, so the spokes never
  cross a giant Mythic fish on the smallest phone) with the giant rarity title (TitleSlam, v3: in
  the top band OVER the fish over the head — `CLIMAX.TitleY` 0.15, 0.18 of the HUD height within
  the side limits, `FishingLayout.topBand` keeps it above the fish (its top is computed from the
  model before the server places it); v5 (D5): BESIDE the fisher and his trophy, on the wider
  side, when no band is left above them or when the letters would be 1.25× bigger there
  (`CLIMAX.TitleBeside`: on a tablet or a PC the band over a big trophy is thin — the word beside
  him is 2× taller), never smaller than `CLIMAX.TitleSide` 24 px, 16 px from the Roblox buttons
  and, without touch, from the chat window and the player list;
  white → rarity → shade fill, a thick outline; Legendary/Mythic letter by letter, each letter
  starts its wave as it lands; a white shine sweeps the word right behind the letters) and, once
  the shockwave is gone (+0.55 s), a light full-screen dim (the card's dim + 0.2; not on phones:
  the fisher holding the trophy stays bright) so rays and letters pop — a title stage of 1.2 / 1.5 /
  1.6 s (Epic / Legendary / Mythic, v3: +0.6 s so the arms-up landing is seen; Common 0.35 and
  Rare 0.4 let the landing pop and halo play before the card) — the word leaves for the banner's place
  0.18 s before the card (`CLIMAX.Lead`, a 0.22 s flight `CLIMAX.Aim`), so when the card is born
  the word already sits at the banner's place and the card grows up under it, never over it in the
  middle of the screen; from the card's birth the word is a transient effect (the title widget
  hides, its copy `FxTitleMorph` settles into the banner and melts as the banner grows out of it) —
  then the card is born at the fish — a card beside the fisher at its own edge on the fish's side,
  growing towards its middle (v5, D2: `CatchFx.birthPoint`), so it never crosses the trophy — and
  settles (position and turn Quint Out, its scale 0.4 → 1.04 → 1 — `CatchFx.birth`; the title's
  spokes fly into it as a shrinking ghost — `CatchFx.ghostRays` — and its own big sunburst grows
  behind it): a landscape trophy card on phones (fish left, name and chips
  right) docked BESIDE the own fisher (v3, UIM-04: `FishingLayout.dockSide` — the wider side: left
  over the thumbstick or right over the action button; the fisher holding the trophy stays in view
  next to it; there the card may be down to `CARD.DockMin` 128 px tall — smaller beside him beats
  bigger over him on the smallest phone; if a huge trophy leaves no room even for that — the square
  card beside him, at least `CARD.DockSquarePhone` 166 px; and if a giant Mythic trophy leaves no
  room for that either — v5: the landscape card where it hides the least of him and his trophy,
  `FishingLayout.leastCover`: pressed to a band's edge, to his edge or level with his middle, taken
  when it hides clearly less than centred; r2 (SIMC-C1-02): `FishingLayout.leastCoverScaled` tries
  `CARD.DockShrink` 1 … 0.85 × `DockMin` and takes the first that hides at most `CARD.DockCover`
  3 % of his box — on phone_small the Mythic card stands right of the giant fish at 0.9, HeldFish
  ≤ 8 % hidden over the whole catch; centred only when nothing is better), the 380 x 384
  square elsewhere — v5 (D1): on a tablet and a PC docked beside the fisher and his trophy too
  (`FishingLayout.cardDock` over the free bands on either side: full height, above the thumbstick,
  the action button or the shown «ДОМОЙ» stack, clear of the tablet's Jump button (it stands higher
  than the action button there), without touch below the chat window and clear of
  the player list — `CLIMAX.ChatBottom` / `ListLeft` / `ListBottom`; the left side a little
  preferred), no smaller than `CARD.DockSquare` 60 % of its centred size and 250 px (if no side takes
  even that — a giant Mythic trophy on a tablet —, it goes where it hides the least of him and his
  trophy, `FishingLayout.leastCover`, when that is clearly less than centred)
  — else centred at the bottom as before. Its gaps are measured by the drawing: 16 px plus its own
  outline (`CatchFx.outline`, thicker than `RimRoom` on big screens; a Mythic card's breath too)
  plus `CARD.EdgeRoom` for the outlines and key chip of the action button and the «ДОМОЙ» column
  (and `CARD.KeyRoom` 3 px more over the action button without touch: its key chip breathes with
  «ЗАБРАТЬ!» — r3, SIMC-C2-04);
  the texts fit the smallest card on one line ≥ 12 px (the name's MinTextSize 12 — never broken
  mid-word —, the landscape card's mutation stamp without «×N», which is on the price chip anyway,
  and on the narrowest landscape cards — under `CatchFx.SHORT_STAMP` 190 px, beside a giant trophy
  — a short word `CatchFx.STAMP_SHORT` («РАДУГА», «НЕОН», «ЗОЛОТО») in a stamp never under 18 px
  tall (r3, SIMC-C2-01: «РАДУЖНАЯ» broke into «РАДУЖНА / Я»); on any card the stamp word is then
  checked against its own line (`CatchFx.stampText` `room`, the caption's width): the first of
  «ЗОЛОТАЯ ×2!» / «ЗОЛОТАЯ!» / «ЗОЛОТАЯ» / «ЗОЛОТО» that fits at 12 px (the small square card beside
  a giant trophy on the small phone said «РАДУЖНА / Я!»),
  and a short «Тапни!» on a landscape card under `CatchFx.SHORT_HINT` 238 px); with a rarity title the
  place is chosen twice (on the landing, where the title flies to, and at the card's birth), both
  times `CARD.DockSlack` px more lenient, so the title never heads for the middle while the card
  is born beside the fisher. The UI v5 card: a Cream sim plate with the chunky
  outline and the light rim, a sky window framed in slate blue, the rarity ribbon (label radius,
  overhanging both sides, the rarity word in outlined white CAPS between two outlined ⭐ tilted
  outwards), the fish on a trophy stand in the rarity's colours (SIM-C1-05: a light cap with the
  fish's soft shadow, the column with an outlined ⭐, a darker base — it punches in under the fish
  0.5 → 1.12 → 1 while its rim flashes), the name white → rarity colours with an Ink outline
  (Mythic a rainbow along the letters), round chips — the weight grey with Ink CAPS, the price gold
  with an overhanging outlined 💵 and italic display digits in the Wallet's notation «$58»
  (`CatchFx.money`; the own trophy's nameplate reads «💵 $518» too — one way to write money) (they flash gold on the landing; on a
  narrow chip, r2 SIMC-C1-05, the icon shrinks to ≥ 0.86 and the label starts 3 px right of it,
  its text floor at most 0.8 of its box — `CatchFx.fitChip`) —, an italic tap hint; the banner's rim flashes as it unrolls and its stars pop in one by one, the
  price chip's rim when it rises; the price bumps with every number. Legendary 1.05x and Mythic
  1.1x the size (on phones the free space is the Mythic's), a dim around it (a card beside the
  fisher: one side band on its side of the screen that melts away towards him — its UIGradient
  "Fade"; no full-screen title dim — he stays bright; none for Common). Behind it the rarity's
  sunburst (Rare+ more rays, Legendary/Mythic a second ring turning the other way), at least
  `CatchFx.RAYS_MIN` 1.6 card heights across (up to `REVEAL.MaxPx`); r2 (SIMC-C1-01): next to the
  fisher the rays are not shortened to the card any more — the CatchRays layer itself is the
  window they show in (`CatchFx.raysClip` / `raysFrame`, ClipsDescendants): the side of him and
  his trophy that holds the card (left / right; above / under him for a spare slot), so they are
  big around the card and never reach him. The rarity shows on the card itself: small rays behind the fish; Epic+ a live
  rim (Epic Grape pulse, Legendary gold sweep, Mythic spinning rainbow — with a mutation it moves
  to the banner's outline and the mutation keeps the card's), Legendary/Mythic a face tinted
  towards the rarity (Mythic: a slow pastel rainbow). The name is born with the card (it slides
  in from the right while the card settles, Quint Out — no blank right half). Then its beats, one
  at a time — Common/Rare (fished dozens of times) ≥ 0.2 s apart, Epic+ ≥ 0.27 s —, each with its
  own motion: rarity (the title flies into the banner and the banner grows out of it at 70 % of the
  flight while the title fades out in 0.08 s and the banner's label fades in — never two readable
  words; without a title the banner unrolls from the middle, Quint Out) → «НОВИНКА!» (a red sticker
  slapped on — 2.4 → 1 with a turn, Back Out, it shivers as it lands with a white ring and a few
  sparks: `CatchFx.slap`; on a card beside the fisher, r2: inside the card at rest and from at most
  `CatchFx.SLAP_DOCKED` 1.6 with a −10° turn, growing where it has room — `CatchFx.fitStamp`
  anchors its UIScale there —, so it never swings over him or the banner's word; on a narrow card
  it is at most half the card wide, ≥ 84 px — `CatchFx.stampMin` —, off the name) → chips (each rises from below with a punch 0.85 → 1.1 → 1, the price
  0.08 s later, the tick a little higher: `CatchFx.punchChips`) → price count-up (a soft ease-out
  that keeps running into the landing: 0.15 s before it ≤ ~92 %) and landing (the chip squashes
  1.25 × 0.85 and springs back, Elastic Out; the price itself is the card's biggest number; 0.12 s
  later «+$4/с» flies OUT of the chip — Back Out to the free space right of the card, never over
  the price or «×N», smaller where tight, over the weight row only as a last resort; r2
  (SIMC-C1-03), a card beside the fisher: above its banner, else beside its outer edge (away
  from him) at the price's height, clear of the chat window and the player list and — with its
  rise (`CARD.PriceFloat.Rise`) — never in the Roblox top-bar row: near the HUD top only right of
  the Menu / Chat pills, `CLIMAX.TopbarRight` (r3, SIMC-C2-03) — `CatchFx.floatSpot`; only if
  neither fits on the fish window's top strip by its right end, right of the «НОВИНКА!» sticker
  (r3, SIMC-C2-02), ≤ 0.3 of the window tall, fading from 0.4 s; no room even there (a narrow
  phone window) — no fly-out, the chip still squashes and sparks — rises and
  fades, the chip bumps as its source — Rare+, a new species or a mutation; Legendary/Mythic 💰
  rain beside the card, behind it (a card beside the fisher: on its outer side only, never on him;
  the coins appear `FishingLayout.EDGE` px under the HUD top, out of the Roblox top bar)
  and a confetti volley; Mythic a rim flare, rainbow sparks and a
  little shake) → mutation (the base price only ticks and breathes one beat; corner stamp, «×N»,
  recount — the party goes to the full price —, the outline in its colours) → the close hint
  «Тапни — забрать!» (Body tier, breathing 0 ↔ 0.15) and the action button's «ЗАБРАТЬ!» (Leaf 👍,
  white halo and rings); then everything calms down and a Mythic card breathes (grows upward, its
  bottom stays). A NEW species of a Common/Rare fish gets a small fanfare (the first catch of a
  new player is usually one): a light dim, brighter rays with gold and green, sparks + a handful
  of confetti + a ping at «НОВИНКА!», a «+$4/с»; a known Common stays calm. On phones the card is
  never shorter than 165 px (the smallest phone's Common card) — 128 px when docked beside the
  fisher. Mythic's confetti comes in three
  volleys (landing, +1 s, the price) under the touch cap. A tap on the card skips to the end, a tap
  at least 0.6 s later closes; the action button (F / R2, the rod) never skips — it only closes
  the settled card, and not while it is being mashed (< 0.3 s since the previous press). Stage 3's
  tank stamp — «В САДОК!» (Water), «ЗАМЕНА!» (Leaf), «ПРОДАНА» under «САДОК ПОЛОН» (Sun: the cause
  is named) — slaps on after the price lands as a sticker like «НОВИНКА!»: −8°, overhanging the
  card's bottom-right corner (the close hint keeps its row, left of it), ≥ 26 px tall with a
  ≥ 16 px line (18 px for the sale) on the smallest phone card, never over the price chip. The card
  closes by itself after `UIConfig.CatchCardTime` (at least 0.6 s after its last beat; a fish sold
  on the spot not sooner than 1.8 s after its stamp, `CatchFx.cardTime`). Closing:
  the card itself is the projectile — it flies into «САДОК» shrinking to a speck (stage 3: a fish
  sold on the spot — `Tank.Result` "sold", a full tank — flies into `Status.Wallet.Money` as a 💵
  instead; no base: the middle of the right column), a 🐟 leaves beside it and they land
  together, a flock of ★ in the rarity colour (up to 6, one frame effect — `UiFx.flyTo { count }`:
  they scatter out of the card and follow 0.06 s apart, a rising tick on each arrival; the close
  flight stays within 3 frame effects) (tap → arrival ≈ 0.35 s; «САДОК» holds its chip meanwhile
  and greets the fish in the rarity colour — the chip rolls like an odometer); right after the
  arrival the trophy over the head flashes once more (`FishingFxController.ReplayOwnTrophy`; the own
  nameplate pops in only now — it stayed hidden while the catch was on screen) and stays ≈ 3 s.
  Rarity tiers (dim, rays, confetti volleys, burst, hold, beat, count, auto-close): `REVEAL` in
  FishingController; the card's tuning (float, new-species fanfare, collect flight): `CARD`.
- **World FX** (FishingFxController + helpers FishingLine / FishShadow / FishLife / FishBody, +
  FishingService for the broadcast): the cast — a white whip streak off the rod tip from the forward
  swing (`Handle.Whip`, synced with the fisher's release), a sparkly trail on the bobber and a
  whoosh, the line trailing it in a curve; the landing «plop» — splash, a low spout, rings, a higher
  splash sound, and the bobber dips ≈ 0.55 stud, pops back past its waterline and settles in a
  damped bob; while waiting the line is slack and breathes, slow ripples and nibbles (the own
  bobber — 2.2× the template — dips half a stud with a ring, drops and a «?»). **A fish shadow**
  (a dark blurred oval + tail, SmoothPlastic, under the water) swims in from afar, circles and
  inspects the bobber, darts in and pokes it on a nibble, lunges under it on the bite and tugs
  away, thrashes under it while reeling (bigger with the own fish's rarity, a flank glint on the
  swings) and flees + fades when the fish is lost or the line is reeled in — the own always, other
  fishers within `Fx.AmbientRange`. The bite: a plunge, a big splash, rings, a bouncing «!» badge
  with stars and a blinking outline on your own bobber, the line jerking slack and tight; while
  reeling a wake, the line taut and trembling sideways (≈ 13 Hz, a few hundredths of a stud),
  pulsing in width and colour; the strike flashes it white, a lost fish red (then it goes slack).
  On a catch a spout, then the fish **leaps out of the water** and flies in an arc (spinning,
  rarity-coloured sparkle trail; it flexes and beats its tail, water drips off it) to above the
  fisher's head — `OwnFishLanded` fires the frame it lands — then the crisp burst (white pop, star
  of thin rays, halo), a nameplate
  (rarity — Rare and up —, name, mutation, price; a Common fish: name and price, bigger; UI v5:
  the reference's billboard words — Montserrat Heavy, no plate, a dark round outline; the rarity
  word white → its colours, the name white, the mutation in its colour, the price in italic
  billboard-yellow digits; sized in studs + pixels; above the fish for others, popping in
  at the landing; beside it — to the right — for your own, hidden while the catch is on screen:
  under the title it would repeat the word, by the card show the final price early; when the
  fish is put away the plate breathes out to 0.8 and fades in 0.14 s where it was — it never
  hangs in the air without its fish, r3 SIMC-C2-06) and the
  rarity aura around the held fish for `FishingRules.HoldFishTime(rarity)` s (≈ 3 s longer than the
  catch card, so your own trophy is still there when the card closes; then, after the arrival on
  «САДОК», `ReplayOwnTrophy` pops it once more: ball, halo, sparks, the own nameplate pops in (no
  replay — 0.5 s after `CounterHold` is released), a chime, a short pillar for Legendary/Mythic —
  on short screens (< 500 px) no pillar and a 0.7× halo, so nothing rings the Wallet; once the
  card has opened the own camera offset rises 0.6 stud (+ half of what the bigger fish grew upwards
  — ≈ 0.5–1 stud) — hidden by the card — so the trophy and its plate clear the Wallet afterwards). **The held
  fish is bigger than life** — `FishingConfig.HeldScale` by rarity (1.6–1.75), never longer than
  `HeldMaxLength` 8 studs (a carp ≈ 3.4 studs, the dragon fish 8; the server scales the model,
  attribute `Scale`), and the leap grows to exactly that size in flight — **and alive**
  on every client in range (FishLife): it bobs, wags its tail and every 1.3–2.2 s flops (the body
  bends from 42 % of its length, plus a small hop and roll, both scaled with the fish), a stronger
  flop on the replay and with every show-off of the fisher; it never leaves its spot or changes
  size — the same trophy for the title, the card and the replay —, and the nameplate only drifts
  gently, never shakes;
  Legendary/Mythic: a light pillar (narrower on your own screen; for everyone else wider with
  distance — ≥ 25 px from the neighbouring pier —, taller with distance — 40 + d / 2 studs, a beam
  to the sky from any pier —, starting above the catcher's nameplate when near, and longer,
  `Fx.PillarTimeOther`; their broadcast toast lands with it, `FishingFxController.OtherTrophy`
  points the HUD chip at it) and a confetti burst, seen by everyone. A lost fish: the line flashes red and goes slack, the bobber pops
  up, a splash and a tail flick away, the shadow flees and fades.
- **The fisher's body** (FisherAnimController + FisherRig / FisherPoses / FisherRod; every client
  animates every fisher within 150 studs, writing joint.Transform in PreSimulation over the default
  Animate pose). Cartoon-sized for a phone (≈ 20 px per stud from the default camera): pelvis hops
  of 0.2–0.55 stud, rod jerks of 15–25°, sideways sways — lateral and vertical moves, which read
  from behind, rather than leans, which do not. The rod is held ≈ 40° to the RIGHT of the bobber
  (`FishingConfig.CastSide` 8–11 studs puts the bobber ≈ 20° right): from behind the whole rod, its
  bend and the line down-left to the bobber read as a «Λ». A 3/4 side-arm wind-up (rod up and
  right, the tip ≤ 15° past vertical; the own bobber hanging at the tip fades near the camera),
  cocked with a tremor until `CastTime` (= cast + `FishingConfig.CastWindUp` 0.3 s, so all clients
  see it), the throw exactly when the bobber leaves the tip, the follow-through held until it
  lands; waiting sway + looking at the bobber + a fidget every 2.5–4 s (weight shift, rod twitch,
  glance, foot tap); bite startle (a hop, shoulders up) and a crouch, the tip and the body jerking
  with the bobber's dips; a strike with a hop; the reel fight (deep crouch, lean back, left-hand
  crank at 2.2 Hz, the rod led after the bobber's thrashing ±18°, the body tugged sideways, the rod
  whipping sideways and bending further for Epic+), a rod pull at the predicted minigame hit, a
  dip on a miss; catch (yank — Epic+ with a hop —, look up at the leap, both hands up under the
  fish over the head, a squat under its weight and a jump, Legendary/Mythic a spin on the spot,
  «pumps»; then every 2.6 s a show-off: an arm pump with a fish flop and a sweep left-right; the
  own replay after the card is a 1.2 s celebration; a held trophy is carried overhead while
  walking), loss (slump: shoulders and head down, the rod dropped to the right, the left arm
  hanging, a stomp, a head shake). The rod bends towards the line under load and whips on the cast
  (a spring, ≈6 Hz); its TipAttachment moves with the bend, so the line and the flying bobber
  follow the bent tip. Poses and timings: FisherPoses (key-pose sheets:
  tools/preview/pose_dump.luau + pose_sheet.py). While walking, torso and head go back to the
  normal animation at once (arms stay posed); every transition is a crossfade, nothing pops. R6:
  no pelvis shift at all and half the waist lean (no waist: RootJoint tilts the legs too). Rules: no uploaded / Studio-registered
  animations, no C0 writes (AnimationConstraint rigs), no per-frame work when nobody fishes
  nearby; far fishers keep no growing lists.
- **The Wallet and «САДОК»** (stage 3; tools/builder/gui/Hud.luau, MoneyController,
  TankButtonController). The Wallet (`Status.Wallet`, the status stack's second row where the catch
  counter was; the stack never grows — phones have no room under it) is the reference's
  panel-less «$0»: an outlined 💵 at −8° and a big italic `MoneyText` number with the display
  outline, the income «+$42/с» beside it in a smaller italic green (Button tier, ≥ 14 px on
  `phone_small`; hidden while the income is 0); the row is sized to its text (per-glyph widths)
  and centred under the badge — a long number first shrinks (never under `Wallet.MinMoney` 22 px),
  then the rate hides. It shows once `DataMode` ≠ "Loading" (no base needed: a queued player owns
  money too); loading for > 3 s — a glass «$…» pill, never a «$0» that looks like lost money.
  Pop-ins after the banner lands: badge → Wallet (0.3 → 1, the 💵 spinning in) → «САДОК», 0.3 s
  apart. The 1 Hz income is PLAIN TEXT (no count-up, no bump: the idle HUD does no frame work);
  every 5 s a small green «+$13» float rises at its right. Money from an event is a celebration:
  coins fly in from where the money came from (a sold card, «САДОК» for a replacement; none for
  a fish sold with the catch — its card already flew in as a 💵), then the number counts up
  (0.6–1.0 s, each new number bumping 1.06), flashes gold, a gold «+$1 234» float and a ping; the
  label never runs ahead of the coins and never steps back. The rate rolls (0.5 s) to the new
  income: down with a short Berry flash after a sale («sold → less income»), up with a gold one
  after a replacement; held while a catch flies in. «САДОК» (`RightButtons.TankButton`, slot 2 of
  the right column, above Home) is a square `Water` `simButton` (Home's recipe: the Small tier
  caption ON its bottom edge; the outlined 🐠 a little smaller and lower right than Home's 🏠, its
  head clear of the chip) with a Cream chip «4/6» inside its top-left corner (italic dark digits,
  ≥ 40 × 20 px; Gold when the tank is full) and the red «!» tucked on its top-right corner (the
  first fish ever: «open me»; out on the first open). The catch's arrival: the chip rolls like an
  odometer, the button bumps (1.45 in the rarity colours), a glow ring in the rarity colour, the
  🐠 squashes and wiggles, a tick; a replacement keeps the chip and sends coins to the Wallet; a
  fish sold on the spot flies to the Wallet, and the Gold «6/6» chip pulses while its card is up
  (`UIConfig.TankButton.SoldPulse` / `SoldPeriod`: the sale is tied to the full tank). A tap while the fish flies is remembered (no «no»
  wiggle) — the panel opens right after the arrival on the new fish's card with a ring; a tap
  during a bite, the minigame or an open card wiggles «no». Water and Sky («ЗАБРОСИТЬ» under it on
  phones) are close hues — the square shape, the 🐠 and the caption tell them apart (wave 2 C's
  `tank_button` render).
- **The tank panel (a sheet)** (stage 3; tools/builder/gui/Sheet.luau — the shell the stage 5 shop
  reuses — + Tank.luau, client helpers Controllers/Sheet and TankCards, TankPanelController). A
  modal sheet that rises from below into its place (no overshoot: it touches the edges of its
  place) and shrinks away (Quad In, never bigger on the way out); NO dim. Its place: 16 px from
  the left, the right column / Jump, the status stack and the bottom; on touch screens also clear
  of the thumbstick (beside or above it); ≤ 900 × 560 and no wider than its cards on a tablet or
  a PC — so it never covers the Wallet (coins fly there), «САДОК» (it toggles) or the stick (a kid
  who walks never hits a sell button). Phones: a glass plate (one quad — secondary info goes on
  glass) with a thin Night strip under the header; tablets and PCs: a Night sim plate. The
  header (≈ 44 px on phones, sized to its texts): 🐠 «САДОК» · the count chip «4/6» (Gold when
  full) · «+$42/с» · «💵 $2 783 📈» (the tank's value now, ticking — «дорожает, чем дольше лежит»;
  no 📈 once every fish is at МАКС; an emoji, not «▲» — italic Montserrat has no ▲ and its
  upright fallback read as a stray glyph) · the Gold market chip «💰 РЫНОК +50%» (only while
  `SellRatePct` > 100; «💰 +50%» when crowded) and a round Berry ✕ (≥ 44 px) overhanging the
  top-right corner; when the bare texts do not fit before the ✕, the rate goes first (the Wallet
  shows it), then the chip's long text, then the word «САДОК». Cards: a scale-sized grid —
  phones one row (scrolls sideways; the clipped last card says «more»), HUD ≥ 600 px two rows
  filled by columns ([1, 2] [3, 4] [5, 6] [🔒]: what scrolls in is the teaser, never a fish).
  A fish card is a sim plate in its rarity's gradient (no shine, gloss or shadow; the Mythic
  rainbow outline turns on a looped tween only while the card exists), laid out from the BOTTOM:
  the sell button (≥ 44 px), above it one row — the income «+$4/с» left, the growth pill «×1.4»
  (or a Gold «МАКС» stamp) right —, the CAPS short name on top (the full name on cards ≥ 150 px
  when it fits; right of a mutation chip «👑 ×2» that overhangs the top-left corner) and the fish
  — the card's hero — in a ViewportFrame in between (built on open, destroyed on close). The sell
  button: Leaf «💵 $45» at home («ПРОДАТЬ $45» on wide cards when the panel's longest price fits:
  one style per panel), Gold at a stall (Sun with a solid white rim on a Legendary card, whose
  yellow → orange plate is the Gold button's own colours — `TankCards.lookToken`), Berry «ПРОДАТЬ?» with a 3 s ring timer while it waits for
  the second tap («ТОЧНО?» where «ПРОДАТЬ?» does not fit) — the card's rate flashes red «−$4/с»
  meanwhile —, Slate ⏳ while the server answers. A tap sooner than 0.4 s after the previous one
  only restarts the arm (mashing never sells). Sold: the card squashes, a gold «+$45» rises out
  of it, an empty card pops in its place with a gold ring, 💵 fly into the Wallet and its rate
  rolls down. Denied: the card wiggles, the server's text in a warning toast (the toast column
  sits over the open sheet). An empty slot is a glass plate (denser on the glass sheet of a
  phone) with a faint 🎣, «ПУСТО», «Поймай рыбу!»; the one locked teaser is Slate — 🔒, «ЕЩЁ
  МЕСТО», «Скоро в магазине». Open: the rise + a stagger of the cards and a nod of the 🐠; the
  sheet closes itself the moment fishing needs the screen (a bite, the minigame, the catch card, a
  fish flying in) — the fisher is never covered. While open it hides `HUD.Fishing` when the
  ActionArea lies under it (or the screen is short): «ВЗЯТЬ» with its red «!» never shows through
  the glass as part of an empty card; back on close.
- **The tank in the world** (stage 3; TankWorldController + its helper TankDisplay, client-only,
  nothing new on the server): the fish live in the court's 12 display aquariums — a real clone of
  `Assets.Fish[FishId][mutation]`, scaled to fit the 6.2-stud cube (≤ 1.6×), its bounding box
  centred on `Display.FishPoint`, head along the slot's ±X turned 18° to the aisle, no collisions,
  queries, touches or shadows; within 70 studs it bobs ±0.12 stud and turns ±6° on ONE looped
  CFrame tween (Sine, 2.4–3.2 s, random phase; the parts welded to the anchored body), beyond 80 it
  stands still; a Rainbow fish shimmers only while alive. Occupied glass is clearer (0.8), the
  light bar and the pedestal's name take the rarity colour; locked displays are dim slate with
  «🔒 Закрыто». Slot events: «in» — the fish grows out of a point, a splash and rarity sparkles
  ABOVE the display (glass hides particles behind it), a light flash; «sold» / «swap» — it
  shrinks to nothing with gold sparkles and «+$45» rises; «mount» — quiet. See «Words in the
  world» for the tags, the sign and the pier word.
- **Words in the world** (UI v5; BaseTemplate builds them, BaseService paints them, HudController
  shows the own base's line; the held fish's nameplate of FishingFxController follows the same
  rules): like the reference's «МАГАЗИН СЛЕДОВ» / «БЕСПЛАТНО!» — big words straight over the
  world, NO plate behind them: Montserrat Heavy, a white → colour `Fill` UIGradient, a THIN dark
  round `Outline` UIStroke in the look's dark shade (`Lip`) — like the reference's 1.5–2 px on a
  33 px cap: 2 px on the owner sign (1.5 for the base name; ≈ 0.1 of the cap across the lagoon,
  less up close), 3 / 2.5 on the gate board at 32 px per stud (r3, SIMC-C2-05). The owner sign
  over each flag (a BillboardGui, MaxDistance 500, sized in studs + pixels so it stays readable far
  away): `OwnerLabel` — the owner's name in white, or «СВОБОДНО!» in `BillboardGreen` while the
  base is free; `BaseLabel` under it — «ЛАЗУРНАЯ БАЗА» in CAPS in the base's own swatch
  (`UIConfig.BaseSwatches`); `YoursLabel` above — «ТВОЯ БАЗА!» in `BillboardGreen`, shown only on
  the owner's own client (HudController, a local write). The gate's name board (SurfaceGuis on
  its cream board, both faces) shows the same two lines in the same letters. They never move or animate (no per-frame work); the colours
  change only when the owner changes.
  Stage 3 words (TankDisplay, the same letters and thin outlines; LightInfluence 0, never
  AlwaysOnTop, sized in studs + pixels; all client-side). Up close a word grows with the world but
  its letters do not: a `UITextSizeConstraint` caps them at a share of the screen height (tags
  16–30 px, the tank sign 22–44 px), so no world word is louder than the Wallet's number. And none
  lies under the HUD: twice a second (and when a toast arrives) each visible word's rect on screen
  is checked against the status stack (the Wallet by its row's content) and the toasts — closer
  than 12 px, the word fades out (0.15 s) and comes back (0.25 s) only once 18 px clear
  (`TankConfig.Display.Clear`; the Wallet's green italic and a world «+$959/с» read as one block):
  - **slot tag** `FxTankTag` — in FRONT of each display's glass at the height of its light bar
    (the bar runs between the lines like a rule; from the aisle the view never goes through the
    glass, which hides billboards behind it): «+$4/с» in `BillboardGreen` over «$45» / «$135
    МАКС» in `BillboardYellow` (italic digits, the lines overlapping a little so the letters are
    bigger); no «▲» after the price (italic Montserrat has no ▲: its upright fallback read as a
    stray glyph; «МАКС» says the price stopped); shown within 28 studs (`TagShow`; further the
    aisle's tags blur into mush), values refreshed once a second within 45 (`TagRange`: fresh by
    the time it shows);
  - **locked word** `FxTankLock` — a dim slate «🔒 Закрыто» on the empty glass, lower than the aisle
    tags, seen from the court gate (80 studs); ONE per arcade side, over the first locked display
    next to the open rows (it moves when more open) — three identical words in perspective piled
    into «За🔒рыто»; the other locked displays keep their pedestal «🔒 Закрыто» and dim bar;
  - **tank sign** `FxTankSign` — over the big show tank, 3 studs above its glass (above the
    «АКВАРИУМ» plaque, mid-frame from the gate rather than in the Wallet's band): «+$42/с» big
    green over «🐠 4/6» smaller white, from the Tank model's attributes, seen from 160 studs; hidden
    on a free base;
  - **pier word** `FxPierTank` (the «садок» at the pier end, K-1) — over the own base's bucket by
    the fishing spot, own base only: «🐠 4/6» white over «+$42/с» green, ≈ 4.4 × 1.6 studs, seen
    within 40; placed above the bucket and its fish tail, a little beyond it from the spot (from
    the fishing camera — right of the rod and the line, above «СМОТАТЬ»); HIDDEN while the bite
    or the minigame runs, while a catch is on screen (`CounterHold`) and while the own character
    holds its trophy (and 0.3 s more, `Pier.TrophyGap`: the trophy's nameplate fades right where the
    word stands); back — it pops in (a punch after an arrival, with one splash at the
    bucket's rim); every 5 s a small «+$13» rises 2.5 studs over it and fades, only while the kid
    stands within 30 studs. No ProximityPrompt at the bucket (a tap target 5 studs from the spot
    would land on the fishing screen);
  - **market word** `FxMarketWord` — «РЫНОК +50%!» in `BillboardYellow` over the hub market's
    «РЫБНЫЙ РЫНОК» sign, seen from 200 studs (the bridge kiosks only have their prompts); a sale at
    a stall bursts coins at its scales;
  - **pops** `FxTankPop` — the rising «+$X» of a sale over a display and of the income over the
    pier word: pop in, rise, fade, gone by themselves (`task.delay`).
- **Theft — the thief** (stage 4; tools/builder/gui/Steal.luau, TheftController + TheftPrompts;
  numbers `UIConfig.Theft`, texts `StealConfig.Texts`). The stock ProximityPrompt «Украсть» /
  «Окунь · +$4/с» (the server's; the client only hides one by its LOCAL `MaxActivationDistance =
  0`). **The thief's bar lives in the BOTTOM band** (`HUD.TheftBar`, centred between the
  thumbstick and Jump, ≥ `Bar.Gap` 16 px from them and the edge, top at `Bar.Top` of the HUD):
  from the thief's camera the display he robs and the fish on his head stand in the upper middle,
  where the status stack and the toasts are — so during a theft the status stack hides
  (HudController, HUD attribute `Stealing`) and the toast column waits (Reserve "thief", the whole
  column; the off-screen trophy chip waits the same on phones). Its looks: the hold — a Night
  plate, 🥷 «КРАДЁШЬ: ОКУНЬ», a thick Berry bar filling to the server's end (one linear tween),
  «Не отходи!» and «1,8 с» in it, the rim flashes for the last second; the carry — a Berry plate,
  🏃 «БЕГИ ЗА ОГРАДУ!», a Gold bar draining over 25 s, «🐕 СОБАКА!» over its right end while
  slowed; a fail — a Berry plate that shakes, 💨 «СОРВАЛОСЬ!» and the server's reason in the Body
  tier; a court hint («Зажми «Украсть»…», why not here with a live «0:24») — on glass, like the
  fishing hint. «ДОБЫЧА!» (`HUD.TheftTitle`, the same bottom band): a Gold → Leaf slam, the sub
  «Окунь — в твоём садке · +$4/с», confetti from over the thief's head and a 🐟 flying from there
  into «САДОК». On the ground: red chevrons crawling to the nearest exit (`Workspace.TheftGuide`,
  Neon, a handful of parts) and a green breathing ring with «ВЫХОД» at the exit. While carrying,
  «ДОМОЙ» shows 🔒 (a press tells why, it never teleports).
- **Theft — the victim** (stage 4; tools/builder/gui/Alert.luau, AlertController + AlertLayout;
  texts `StealConfig.Texts.Alert` / `Result`). **The alert plate** `HUD.TheftAlert` — at the top
  of the toast column (Reserve "alert"; toasts below it at the band gap, never on the own fisher):
  a Berry sim plate ≤ `Theft.Width` × W and `WidthMax`, 🚨 (hold) / 🏃 (carry) overhanging its
  left end, «ВОР В САДКЕ!» / «Ника крадёт: Окунь» (carry: «ВОР УБЕГАЕТ!» / «… — жми ЩИТ!»), on the
  right a Guard **«🛡️ ЩИТ» — the largest target on the screen** (≥ `ShieldMin` 56 px and ≥
  `ShieldShare` of the plate; a Slate «⏳ 1:12» on cooldown) and a Grape «🏠 ДОМОЙ» (≥ 44 px). It
  pops in with a shiver (a quiet repeat — no shiver). On a phone where the plate would lie on the
  own fisher it becomes **the compact pill** «🚨 ВОР! ОКУНЬ» + a full-height ЩИТ, placed by
  AlertLayout in the first free spot (≥ 16 px from the fisher, his bobber, the status plates,
  the right column, Jump, the stick, the fishing widgets and the thief's bar). **The alert's
  zero-layout layers** come from the first frame and take no room: a thin Berry edge pulse
  (`Theft.Edge`, its own clipped layer under the topbar; asleep while the HUD's own vignette
  glows), the column's «ДОМОЙ!» with red rings, the «ЗАЩИТА» button turned Berry «ЩИТ!» with
  rings (one tap — the shield, even mid-minigame), the red pier word «🚨 КРАДУТ!» and 3 pings.
  The plate never takes the minigame's input. **The alert outranks the catch card**: a card up
  when the alert starts takes its normal close path (the 🐟 still flies into «САДОК») and the
  plate pops in `Theft.CardAfter` later; a catch during the alert hurries its card the same way;
  a card or a sheet that appears hides the plate until it leaves — the plate never draws over
  them. The end: «Украдено: Окунь (Ника)» (the big theft toast) + «Садок отдыхает 1:30 — не
  украдут» + ONE tip, or «Вор пойман — рыба спасена!» (confetti) / one «Щит спас рыбу! 🛡️ 1:00».
- **Defence** (stage 4; Hud.luau + tools/builder/gui/Defence.luau, DefenceController +
  DefenceCards; texts `DefenceConfig.Texts`): **«ЗАЩИТА»** — the right column's third square (a
  Guard `simButton` with 🛡️, above «САДОК»; Home's recipe), Berry «ЩИТ!» during an alert, a dark
  draining veil with «2:59» on cooldown, «ГОТОВ!» on its caption when ready again. **The shield
  chip** `Status.BaseBadge.ShieldChip` «🛡️ 0:42» docked at the badge's right end (≤ `ChipMax`
  90 px): solid Guard for the shield, glass for the other protections, a Sun flash and bob in the
  last 10 s. **The «ЗАЩИТА» sheet** `HUD.DefencePanel` on the Stage 3 sheet shell (one sheet on
  screen at a time): four Pond cards Щит · Собака · Сигнализация · Замок — an icon disc, the CAPS
  name, one effect line, a buy button (Guard «ВКЛЮЧИТЬ» / glass «🛡️ 0:42» / Slate «⏳ 2:59» for
  the shield, Berry «ЩИТ!» during an alert; Gold «💵 $6 000» → Berry «КУПИТЬ?» → a flat Leaf
  «✔️ КУПЛЕНО» stamp for the rest; Slate with «ЕЩЁ $3 000» under the finger when money is short). A buy sends 💵 from the Wallet into the card («−$6 000»). In the
  world (TheftWorldController, client-only, 0 server parts): the mast lamp blinks dark ↔ hot at
  2 Hz (never faster than 3 Hz), the bought siren spins two red SpotLights + Beams and beeps, the
  thief of an alarmed base gets a Berry `Highlight` (AlwaysOnTop for the owner, Occluded for the
  rest; ≤ 1 per thief) and «ВОР!», the shield (and only the shield) a ForceField dome over the
  court (≤ 2 on phones; clearer when the camera is near or inside), the dog's «ГАВ!» / «💤».

## 4. Budgets (phones first)

- At most ~60 temporary GUI objects alive at once from effects (confetti 40 max on phones, 60 on PC);
  everything destroyed when done. No RenderStepped/Heartbeat connection while nothing animates.
- World: at most 2 ParticleEmitters active per player at a time; parts for ripples/pillars are
  client-side, CanCollide/CanQuery/CanTouch false, CastShadow false, destroyed after use (ripple
  rigs — part + SurfaceGui + frames — go back to a pool of ≤ 8 per fisher and are reused).
- World perf (v3 fixes F3/F5/F7/F9): bobbers beyond `Fx.Range` draw no line and are moved every
  0.25 s (or on a state change), not every frame; a rainbow fish held by a character is
  repainted ≤ 5 times a second in 12 hue steps (a step that did not change is not written) and
  only within 60 studs — its Color rebuilds the character's merged mesh; the trophy's moving
  PointLight (rarity / Neon glow) exists only on its fisher's own client; the shore foam rings'
  breathing (the stroke only) is checked twice a second and written only when it changed by 0.05+.
- Fishing world FX v3 (measured in tests/fishing_fx.test.luau): everything rides the one shared
  RenderStepped of FishingFxController (gone when nothing animates). Fish shadow: 2 parts + 1
  BulkMoveTo per bobber per frame (own always, others within `Fx.AmbientRange`); line: ≤ 6 Beam /
  Attachment writes per frame; whip: 1 Trail + 1 Attachment for ≈ 0.5 s; leap: 1 BulkMoveTo of
  the fish's parts (≤ 30) per frame for ≈ 1 s + ≤ 12 drip balls; held fish: within 60 studs 1
  HoldWeld C0 + 1 C0 per bending part per frame (client-only writes, the server never sees them),
  up to 120 studs one write every other frame, beyond that nothing (a 0.5 s timer, no
  connection). New connections: CharacterAdded per player, ChildAdded per character, one
  FishingState listener.
- Fisher animation: one PreSimulation connection for all fishers, only while someone within 150
  studs fishes / holds a trophy / finishes a short move; ≈15 Transform writes + ≤ 14 rod-weld C0
  writes per animated fisher per frame, no Instance created per frame.
- Stage 3 (measured with 8 players and full tanks, wave 3 E audit): a client builds the display
  fish only of bases within `Display.Range` 180 studs (torn down beyond 210, ≤ 3 quiet builds per
  0.5 s check) — the courts sit 306 studs apart on a 399-stud ring, so at most 2 bases at once
  (half way between two courts) and only the own one from its pier: 96 parts for 6 mixed fish
  (≤ 20 per fish, the dragon), 191 for 12, ≈ 380 at the worst point between two full 12-slot
  courts — far under `PartBudget.RuntimeReserve.TankFish` 1920. Idle, it adds NO per-frame
  connection (a 0.5 s `task.delay` chain measures, a 1 s one refreshes the tags; the panel ticks on
  its own 1 s chain while open) and one looped tween per display fish within 70 studs (6–12 in the
  own court, none from the pier); the only frame hook it may cause is FishingFxController's
  rainbow repaint (≤ 5 Hz) while a Rainbow fish is alive on screen (in the court within 80 studs,
  or its card in the open panel). ≤ 2 ParticleEmitters per player; ≤ 60 temporary GUI objects
  for a sale's juice; after closing the panel the connections are back to the baseline. The
  server adds no parts and no per-frame connection (the income runs on one `task.wait` loop).
- Animations never block input; widgets keep their names (controllers and tests find them by name)
  and stay inside the layout rules of tools/builder/Gui.luau (above the Roblox hotbar, left of the
  Jump button, out of the status stack).
- Reduced motion is not a goal, but nothing may flash faster than 3 times per second.

## 5. Built-in content we may use (no uploads)

Particle textures: `rbxasset://textures/particles/sparkles_main.dds`, `smoke_main.dds`,
`fire_main.dds`, `explosion01_core_main.dds`, `explosion01_shockwave_main.dds`.
Sounds (client content; harmless if a file is missing): `rbxasset://sounds/swoosh.wav`,
`rbxasset://sounds/electronicpingshort.wav`, `rbxasset://sounds/impact_water.mp3`,
`rbxasset://sounds/action_swim.mp3`, `rbxasset://sounds/button.wav`, `rbxasset://sounds/clickfast.wav`.

## 6. API (UI v5 «Симулятор»; motion and FX from v1–v4)

Where things live:

| what | file | side |
|---|---|---|
| colours: palette tokens, rarity/mutation styles, toast kinds, confetti mixes, the font, the sim shape numbers, motion defaults, FX limits | `src/ReplicatedStorage/Shared/Config/UIConfig.luau` (pure: Color3 only) | both |
| builder helpers (sim buttons and plates, glass, badge, stat, title, labels, icons, gradients) | `tools/builder/gui/Theme.luau` (reads UIConfig via `U.loadPure`) | Lune |
| motion library (+ recolouring) | `src/ReplicatedStorage/Shared/UiFx.luau` | client |
| CAPS for Cyrillic | `src/ReplicatedStorage/Shared/TextUtil.luau` (`TextUtil.upper`) | both |
| reference implementation | `gui/Hud.luau` + `HudController` + `NotifyController` | both |
| tests | `tests/ui_sim.test.luau` (Theme kit, no sim), `tests/uifx.test.luau`, `tests/hud_style.test.luau`, `tests/fishing_ui_style.test.luau` | Lune / sim |
| GUI previews (fonts: Montserrat + italic, Twemoji) | `tools/preview/gui_render.py`, `tools/preview/README.md` | Python |

### 6.1 UIConfig (one source of colours and numbers)

`Ink`, `White`; `Palette.<Leaf|Sky|Berry|Sun|Gold|Grape|Pink|Mint|Slate|Night|Cream|Pond|Water|Coal>` =
`{ Top, Bottom, Lip }` (§1; Lip = the outline colour, the dark shade of the hue) and
`Palette.Glass = { Top, Bottom, Lip, Alpha = 0.5 }` (glass: a black face at Alpha transparency,
no outline); `Rarity.<Common|Rare|Epic|Legendary|Mythic>` = `{ Top, Bottom, Lip, Rainbow, Rays =
{…}, Confetti = {…}, ConfettiCount, Flash }`; `Mutations.<Gold|Neon|Rainbow>` = `{ Top, Bottom, Lip,
Icon, Effect = "sparkles"|"pulse"|"rainbow" }`; `Rainbow` (7 hues), `Confetti` (vivid mix);
`BadgeRed` (the «!» badge), `MoneyText`, `BillboardYellow` / `BillboardGreen` (the next passes);
`ToastKinds.<info|success|warning|danger|base|Legendary|Mythic>` = `{ Token, Icon, Rainbow?, Big?,
Life?, Priority? }` (danger icon 🚨; unknown kinds render as info); `KindColors` (flat colour per
kind = palette Bottom); `NoBaseColor`; `BaseSwatches.<Id>` and `swatchFor(color) -> swatch` (base
colours, §1); `Font = { Family = Montserrat }`; `Type = { Title = 20, Button = 17, Body = 15,
Small = 14 }`, `TypeHeight = 390`, `TypeMaxScale = 1.6` (§1); `CatchCardTime.<rarity>` = 2.2 /
2.8 / 3.4 / 4.2 / 5.1 s (client-only auto-close of the catch card); `ToastDuration`, `MaxToasts =
3`, `MaxToastsTouch = 1`, `MaxToastsPhone = 1`, `ToastGap = 0.7`; `Sim = { Radius 0.08,
PlateRadius 0.3, Stroke 6, MinorStroke 4, Rim 2, RimAlpha 0.5, GlassAlpha 0.5, Gloss 0.8, ShadowY
0.08, ShadowAlpha 0.55 }` (§6.2; tune the look here, both sides follow); `Motion = { Press, Hover,
Pop, Punch, Out, Morph, Breath, Shine, Bob, Sway, Wobble, Roll, Fly, Ring, RimFlash, Reduced }`
(§2: UiFx's defaults); `Fishing = { PipDone (64,200,96 — the e2e bot looks for it), TrackBottom,
PipShade, NeedleShade, NeedleGhost, Muted, Guide, ZoneGlow, TimeBar = {cool, Sun, Berry} }` (fishing colours
outside the palette); `Fx = { ConfettiMaxTouch = 40, ConfettiMax = 60, ShineInterval,
FlashMinInterval = 0.34, StrokeHeight = 720, StrokeMax = 1.2, TextStrokeMax = 1.0, TextStrokeMin =
2, FovPunchMax = 8, SoundPool = 4 }`. FishConfig's rarity/mutation `Color`s stay the flat
colours the stage-2 tests check; use `UIConfig.Rarity` / `Mutations` for gradients and FX.

### 6.2 The sim surface (structure contract shared by Theme and UiFx)

```
<Root>       any GuiObject, BackgroundTransparency 1; attributes CandyFace = "<face name>"
             ("Face"; the base badge: "Swatch"), CandyRadius, CandyStyle = "sim" | "glass",
             CandyHome = "glass" (built by Theme.glass: dark tokens keep it glass)
  Shadow     (opts.shadow) a soft Ink copy of the shape ShadowY lower, ZIndex z − 1
  Lip        the OUTLINE carrier: a full-size Frame with no fill (BackgroundTransparency 1;
             BackgroundColor3 = the swatch's Lip, kept for readers), UICorner, UIStroke (Border,
             Round joins, colour = Lip, BaseThickness = Sim.Stroke 6 — chips MinorStroke 4), ZIndex z
             (SZ.Lip 1)
  <Face>     Frame, FULL size, ZIndex z + 1, white + UIGradient "Fill" Top → Bottom (Rotation 90),
             UICorner; glass: BackgroundTransparency Alpha, the outline and the rim transparent
    Gloss    (opts.gloss) a white band in the top half, UIGradient "Fade" Gloss → 1
    Rim      a full-size Frame with a UIStroke (white, BorderStrokePosition Inner, RimAlpha,
             BaseThickness Sim.Rim 2) — the light rim just inside the outline
    Shine    full-size white overlay, Visible = false until UiFx.shine sweeps it; UIGradient
             "Band" (Rotation 20, Offset (−1, 0) = hidden)
  …content   Icon / Caption / Label at SZ.Content (3); overlays at SZ.Overlay (5), text over
             overlays at SZ.Top (6); the badge at SZ.Top + 1
```

A drop-shadow twin of a label (`Shadow = true`) is a SIBLING named `<Name>Shadow` (attribute
`ShadowOf = <Name>`, Ink text at 0.35, 7 % of the height lower, ZIndex − 1): with ZIndexBehavior
Sibling a child would draw over its parent. Runtime colours (built with `color`,
`UiFx.setCandy(root, Color3)`) become the swatch `UIConfig.swatchFor(colour)`; the base badge
uses `BaseSwatches`. Anything that must appear *behind* a widget (glow, rays, the ring timer) is a
child with ZIndex 0. Outlines are drawn for a 720 px tall screen: every UIStroke made by
Theme/UiFx carries a `BaseThickness` attribute and `UiFx.fitStrokes(hud)` (HudController) scales
them to the real screen height (§1), including widgets cloned later. Text tiers are fitted the
same way by `UiFx.fitText(hud)`. Note: Lune stores `UICorner.CornerRadius` as the four per-corner
radii, so in RbxSim read `TopLeftRadius` (or `CandyRadius`), not `CornerRadius`.

### 6.3 Theme (builder, `tools/builder/gui/Theme.luau`)

| function | what |
|---|---|
| `Theme.UI`, `Theme.P`, `Theme.TYPE`, `Theme.INK`, `Theme.WHITE` | UIConfig, its palette, the type scale, Ink, white |
| `Theme.SZ` | ZIndex layers inside a sim root: `Behind 0, Lip 1, Face 2, Content 3, Overlay 5, Top 6` |
| `Theme.FONT`, `Theme.FONT_ITALIC`, `Theme.MIN_TEXT`, `Theme.HOTBAR` | Montserrat Heavy and Heavy Italic, 12 px, 0 px (v3: the Roblox hotbar is off) |
| `Theme.STROKE`, `Theme.MINOR`, `Theme.TIER_OUTLINE`, `Theme.DISPLAY_OUTLINE`, `Theme.TITLE_OUTLINE`, `Theme.ICON_OUTLINE` | 6 (shapes), 4 (small parts), text outline per tier `{Title 3.5, Button 3, Body 2.5, Small 2.5}`, 4.5 (display numbers and words), 8 (huge titles), 3 (emoji contour) — px at 720 |
| `Theme.sim(root, token, opts?)` → face | makes `root` a sim surface (§6.2); opts: `radius` (Sim.Radius), `round`, `stroke` (Sim.Stroke; 0 = none), `rim` (false / px), `color` (runtime colour → `swatchFor`), `faceName`, `shine` (false to omit), `gloss`, `shadow`, `transparency`, `z` (SZ.Lip) |
| `Theme.glass(root, opts?)` → face | the reference's timer pill: `sim` in the Glass look (black face at `alpha`, no outline, no rim; radius 0.5); `edge` = px of a faint Ink outline (grooves), `edgeAlpha` |
| `Theme.simButton(parent, name, token, props)` → TextButton | a sim button with `Icon` / `Caption`; props: TextButton props + `Layout` ("row": icon left, caption right; "square": a big icon, the caption ON the bottom edge — Home; "round": a round button; "stack": icon over caption), `Icon`, `Caption`, `Tier`, `Radius`, `Square`, `MaxTextSize`, `MinTextSize`, `SimOpts` |
| `Theme.plate(parent, name, token, props)` → Frame | a sim plate with an outlined emoji overhanging its left end and a `Label`: props `Icon`, `IconScale` (1.15), `Socket` (the icon in a transparent "IconSocket"), `Text`, `Tier`, `Italic`, `MaxTextSize`, `LabelProps`, `Radius` (PlateRadius), `Glass`, `Color`, `SimOpts` |
| `Theme.badge(parent, name?, props?)` → Frame | the red «!» disc (BadgeRed, outline 3, rim 1.5, "Mark" «!»), hidden, centred on the host's top-right corner, half its height, ≥ 22 px — show it with `UiFx.badgeBob` |
| `Theme.stat(parent, name, emoji, props)` → Frame | a panel-less stat: an outlined `Icon` (−8°, round corner for glow rings) and a big italic white `Label` (display outline, TextFill white → white so a controller can tint it); props `Text`, `IconScale` (1.2), `MaxTextSize` (48), `MinTextSize` (16), `Color` |
| `Theme.title(parent, name, props)` → TextLabel | a huge outlined title with no panel: `label` with `Outline` 8, `Shadow = true`, `MaxTextSize` 72; `TextGradient` for a coloured fill |
| `Theme.label(parent, name, props)` → TextLabel | white Montserrat Heavy text, Ink outline; extra keys `Tier` (type scale: attribute `TextTier` + constraint TYPE[tier] / −2, and at least `TIER_OUTLINE[tier]` unless `Outline = false` or `TextStrokeTransparency = 1`), `MaxTextSize`, `MinTextSize`, `Outline = px` (UIStroke "Outline" on the text), `OutlineColor`, `TextGradient = {top, …}` (UIGradient "TextFill"), `Italic`, `Shadow` (the `<Name>Shadow` twin) |
| `Theme.icon(parent, name, emoji, props?)` → TextLabel | emoji label with the Ink contour (`Outline` px, default 3; false = none; a faint glyph gets none), Rotation 0, ZIndex Content |
| `Theme.socket(parent, name, emoji, props?)` → Frame | a transparent holder (RelativeYY) with the outlined emoji (`IconName`, default "Icon"; `IconOutline`); emoji "" = empty |
| `Theme.shine(face, radius)` | the hidden Shine overlay on its own |
| `Theme.rarityGradient(parent, rarityId, rotation?)` | rarity gradient; Mythic gets rainbow stops + attribute `Rainbow = true` (animate with `UiFx.rainbow`) |
| `Theme.gradient`, `Theme.multiGradient`, `Theme.sequence`, `Theme.numbers`, `Theme.lighten`, `Theme.darken`, `Theme.swatch`, `Theme.corner`, `Theme.stroke(parent, px, transparency?, color?)`, `Theme.outline(parent, px, color?, transparency?)` | small helpers; `stroke` / `outline` carry `BaseThickness` |

### 6.4 UiFx (client, `require(ReplicatedStorage.Shared.UiFx)`)

"timers" = TweenService + `task.delay` only (no connection); "frame" = the shared scheduler (one
RenderStepped connection for all running frame effects, disconnected when none runs).

| function | kind | notes |
|---|---|---|
| `press(button, {scale?, peak?, shade?, sound?, icon?, hover?})` → unbind | 3–4 conns | §2 press: squash `scale` (0.9) + the face darkens to `shade` (0.8); release → overshoot `peak` (1.08, ≤ `Press.MaxGrow` px) → Back-Out 1, the `icon` child ("Icon"; false = none) kicks unless it has `IconBusy`; `hover` (default: no touch screen) 1.05 while the mouse is over; release is caught outside the button too |
| `popIn(gui, {from?, time?, delay?, rotate?})` | timers | UIScale from → 1, Back Out (0.3 s), optional rotation → rest; drives a `<Name>Shadow` twin too |
| `popOut(gui, {time?, to?, destroy?, hide?, swell?})` | timers | swell 1.06, then Back In to `to`, then destroy / hide |
| `punch(gui, {from?, peak?, up?, settle?, delay?})` | timers | from (0.84) → peak (1.1, Quad Out) → 1 (Back Out); a new punch cancels the old second step |
| `snapIn(gui, {drop?, delay?, squash?, sound?})` | timers | drop from `drop` (8) px above, squash 1 + `squash` (0.08) on contact, Back-Out spring, tick |
| `rimFlash(root, {delay?, time?, bump?, sound?})` | timers | §2 rim flash |
| `iconPop(root, from?)` | timers | the root's (or its face's) `Icon` punches from (0.7) → 1.15 → 1 |
| `morphFlash(root, color?)` | timers | a white "FxMorph" overlay on the face 0.4 → 1 (0.2 s) + `iconPop` |
| `recolor(root, look, time?)` | timers | `setCandy` with a cross-fade of the old gradient (0.16 s) and an outline colour tween |
| `setCandy(root, token \| swatch \| Color3)` | — | recolour a sim surface (gradient, outline, rim) and switch glass ↔ solid (§1); resets the press shade |
| `setText(label, text)`, `twinOf(label)` | — | text for a label and its shadow twin; the twin or nil |
| `bump(gui, peak?, time?)` | timers | 1.22 → 1 spring (counters, rewards) |
| `slam(gui, from?, time?)` / `stamp(gui, rotate?, time?)` | timers | 2.2 → 1 + small shake / 3 → 1 with a −16° turn |
| `pulse(gui, peak?, period?)` → stop | timers | 1 ↔ 1.08, Sine, 0.8 s |
| `breathe(gui, {peak?, period?, when?})` → stop | timers | one breath 1 → 1.04 → 1 every 1.8 s while visible and at rest (the action disc: 1.05 every 1.4 s, ≤ 4 px a side) |
| `bob(icon, {lift?, every?, hops?, when?})` → stop | timers | the icon hops through its AnchorPoint every 2.2–3.0 s (or `hops` times) |
| `sway(gui, {angle?, period?})` → stop | timers | ±1.5° rotation loop (one tween) |
| `wobbleLoop(gui, {angle?, bump?, every?})` → stop | timers | wiggle ±12° + bump 1.12 every 2.8–3.6 s |
| `badgeBob(badge)` → stop / `badgeHide(badge)` | timers | the «!» badge in (punch, ring, tick) and wobbling / out |
| `staggerPop(items, {from?, gap?, time?, delay?})` | timers | pop a list one after another |
| `swapText(label, text, {out?, inTime?, lift?})` | timers | the slot-machine roll (a "FxSwap" ghost of the old text) |
| `flashText(label, color, time?)` | timers | TextColor3 → colour → rest (≥ 0.34 s apart per label) |
| `textWidth(text, px)` | — | estimated width of Montserrat Heavy text at TextSize `px`, per glyph (capitals ≈ 0.68, small letters ≈ 0.59, digits and Latin narrower, spaces and punctuation ≈ 0.25, emoji ≈ 0.82 of the size): plates sized to their text before it is drawn (toasts) |
| `ringTimer(gui, duration, {colors?, thickness?, pad?, z?, track?})` → stop | timers | §2 ring timer ("FxRingTimer" with Left / Right halves, strokes drawn inward; pad ≤ 0 + z: inside the widget's outline; track: a dark "Track" ring under it; the colour stages chained — the second starts from a `task.delay` the stop cancels) |
| `wiggle(gui, angle?, swings?, time?)` | timers | ±6°, 3 swings, 0.4 s; restarts cleanly, returns to the rest rotation |
| `shake(gui, amount?, time?)` | timers | Position jitter ±1.5 %; **no effect inside a UIListLayout** (use wiggle there) |
| `shine(gui, time?)` | timers | sweeps the surface's `Shine.Band`; others get a temporary overlay with the same UICorner |
| `shineLoop(gui, {interval?, time?, delay?, when?})` → stop | timers | idle shine every 3.5 s while visible (and `when()`) |
| `glowRing(gui, {color?, time?, scale?, thickness?, filled?, loop?, interval?, z?})` → stop | timers | expanding ring (or a filled copy behind) 1 → 1.5, fading; stop also fades this call's live rings in 0.1 s |
| `ripple(gui, color?)` | timers | small one-shot ring for taps |
| `rays(gui, {colors?, count?, speed?, size?, maxPx?, width?, transparency?, glow?, halo?, breathe?, grow?, hole?, growFrom?, z?})` → `Rays` | timers | sunburst behind `gui` (ZIndex 0); `rays()` / `rays.stop()` removes, `rays:Destroy()` for Trove, `rays:settle({alphaAdd, spinMul, time})` calms it, `rays.holder` = the FxRays frame |
| `confetti(container, {count?, colors?, origin?, spread?, power?, duration?, z?})` → stop | frame | ≤ 40 alive on touch devices, ≤ 60 otherwise (`confettiCap()`, `liveConfetti()`) |
| `confettiPop(container, {same options})` → stop | timers | the same pieces on tweens only — for moments when the rest is idle (joining, the base banner) |
| `burst(container, {count?, colors?, origin?, power?, time?, z?, size?})` → stop | frame | round sparks flying out of `origin` |
| `sparkles(gui, {icons?, rate?, size?, area?, duration?, z?, outside?})` → stop | timers | ✨/⭐ popping around the edges; `outside` — only beside the element, left and right, never over it (text plates: toasts, the mutation stamp, banners — r4 ART-02; not under a toast either: the avatar's head is there) |
| `floatText(container, text, {position?, size?, color?, colors?, rise?, time?, rotate?, z?, to?, travel?, anchor?})` → label | timers | italic «ОТЛИЧНО!», «+1»: pop, rise 8 %, fade (0.8 s); with `to` it first flies out of `position` to `to`; `anchor` — the point `position` names and its UIScale grows about (a slam from its far edge) |
| `countUp(label, from, to, time?, format?, {bump?})` → stop | frame | Quad Out; `bump`: each new number bumps 1.06 → 1 (≤ 12 Hz) |
| `flyTo(layer, from, to, {text?, texts?, color?, time?, size?, arc?, count?, gap?, onEach?, onArrive?})` → stop | frame | §2 fly-up: one frame job for all icons |
| `rainbow(gradient, {speed?, colors?, spin?, bounce?})` → stop | frame | hue cycle (30 Hz); `bounce` — there and back (a partial rainbow: the last colour never blends into the first); stop restores the colours |
| `timerBar(fill, duration, colors?)` → stop | frame | width 1 → 0, green → yellow → red |
| `flash(layer, color?, time?, from?, hold?)`, `flashBig(layer, color?)` | timers | full-screen flash, at most 3 per second |
| `shockwave(layer, origin, {color?, colors?, size?, time?, thickness?, glow?, z?, from?})` | timers | the landing hit at `origin`; the rings start at `from` layer heights (≥ 0.3: outside what landed) |
| `fovPunch(deg, tIn?, tOut?, easeIn?)` → stop | frame | the ONLY writer of `Camera.FieldOfView` (sum clamped to ±8°) |
| `edgeVignette(layer, color \| {colors}, alpha, period?, opts?)` → stop(fade?) | timers | 4 edge bands ("FxVignette"); opts `fadeIn`, `from`, `build`, `cycle`, `pulseTo`, `hold`, `fadeOut`, `size`, `z` |
| `trail(gui, {count?, lag?, transparency?, last?, color?, width?, taper?, height?, z?})` → stop | frame | ghost copies following a moving widget (the minigame needle): each `lag` s behind the one before, transparency `transparency` → `last`, width `width` → `taper` of the widget's, `height` of it, in `color`, at ZIndex `z` |
| `cameraShake(amplitude?, time?)` → stop | render step | gentle translation-only shake (Legendary/Mythic) |
| `fadeOut(gui, time?)` | timers | every background/text/stroke/ViewportFrame under `gui` to transparent |
| `fitStrokes(root)` → unbind, `strokeThickness(stroke)` → px | 2 conns | §6.2 (restore a stroke to `strokeThickness`, never to a live value) |
| `fitText(root)` → unbind, `textSize(tier)` → px | 2 conns | the type scale for every `TextTier` label, also ones added later |
| `reducedMotion()`, `setReducedMotion(bool?)` | — | §2 reduced motion |
| `sound(name, volume?, pitch?)`, `arpeggio(rarityId, volume?)` → stop | — / timers | "click", "tick", "pop"/"ping", "swoosh", "splash", "swim" or an rbxasset id, 4 pooled copies; the rarity arpeggio |
| `scaleOf(gui)`, `faceOf(root)`, `tween(…)`, `stagger(items, gap?, fn)`, `sequence(colors)`, `sampleColors(colors, k)`, `lighten`, `darken`, `schedule(step, cleanup?)` → stop, `activeJobs()` | — | helpers; `scaleOf` returns the shared UIScale "FxScale" (FishingController uses the same one) |

### 6.5 HUD contracts (v2–v5)

- **The catch hold** (stage 3 re-points the old counter contract): FishingController sets the HUD
  ScreenGui's number attribute `CounterHold` (= `Total − 1` from the Caught data) synchronously on
  "Caught", before the leap and the card, and the string attribute `CounterIncoming` = the rarity
  id while the 🐟 flies; it clears both when the card (or its 💵) arrives. `CounterHold` also means
  «a catch is on screen» to NotifyController, the tank panel (it closes / defers its open), the
  pier word (hidden) and MoneyController (it holds a catch's sale back). The card flies with
  `flyTo(hud, from, target, {onArrive = …})`: the target is `RightButtons.TankButton`, or
  `Status.Wallet.Money` (with a 💵) when `Tank.Result` is "sold".
- **«САДОК»** (`HUD.RightButtons.TankButton`: `Icon`, `Caption`, `Count.Label`, `Badge`):
  TankButtonController only. The chip «4/6» comes ONLY from the Player attributes `TankCount` /
  `TankSlots` (the Caught payload's `Tank` only picks which arrival plays); it is frozen at its
  count before the catch while `CounterHold` is set and plays the arrival when it clears ("stored":
  the roll, bump, ring, 🐠 squash; "replaced": a wiggle, a ring, then `MoneyController.Celebrate
  (Tank.Price, TankButton, { Rate = "up" })` and the toast; "sold": nothing). Without `CounterHold`
  (stage 4: a fish added outside a catch, TankEvent "Stored") the same arrival plays by itself.
  The onboarding «!»: `UiFx.badgeBob(Badge)` after the first fish ever (`Tank.First`),
  `UiFx.badgeHide` when `HUD.TankPanel` first becomes visible — session-local, no remote. Visible
  with a base and loaded data; it pops in on its spot (never animate the column's Position: the
  fishing layout reads it). Press → `TankPanelController.Toggle()`.
- **Wallet** (`HUD.Status.Wallet`: `Money.{Icon, Label, Back}`, `Rate`): MoneyController is the
  ONLY writer of `Money.Label` and `Rate`. Anything that credits money calls
  `MoneyController.Celebrate(amount, from: GuiObject?, { Rate = "down" | "up" }?)` exactly once
  per credited amount (the panel for a manual sale, «САДОК» for a replacement; MoneyController
  itself for a fish sold with the catch); Celebrate never adds to the label — the money is
  already in the Player attribute `Money` — it holds the not-yet-shown coins until the first
  icon lands, then counts up. `MoneyController.CatchToast(text, kind, look?, delay?)` shows a
  catch toast once the own trophy has left the head. `MoneyController.Shown()` is the number on
  the label (tests, scenarios). Money values: `TankRules.FormatMoney` («$1 234», «$1.23M» …),
  rates `TankRules.FormatRate` («+$0.8/с», «+$42/с»).
- **The sheet** (`gui/Sheet.luau` builds `<Name>.Panel.{Strip, Header.{Icon, Title, …}, Close,
  Cards}`; `Controllers/Sheet.luau` drives it): `Sheet.new(hud, root, { Layout, Token,
  contentWidth, onPlace, onClose, onClosed })`, `:Open() -> boolean` (false while `:Busy()` is
  "fishing" or "hold"), `:Close(reason)`, `:Place()` (a ViewportSize change), `:Fit()`. Its place
  and its parts are computed in px and written as scales; it closes itself (reason "fishing")
  for the bite, the minigame, the catch card and `CounterHold`; everything it creates while open
  lives in its Trove. The stage 5 shop builds on it the same way the tank panel does.
- **Tank panel** (`HUD.TankPanel.Panel.Header.{Icon, Title, Count, Rate, Total, Market}`, `Close`,
  `Cards.{CardTemplate, EmptyTemplate, LockedTemplate}` → cloned as `Card<slot>` / `Locked`):
  TankPanelController (`Toggle`, `Open(focusUid?)`, `Close`, `IsOpen`; tests: `Relayout`, `Card`,
  `Stats`). Its numbers come from the own base's slot attributes (refreshed on each slot's
  `Event` only) and `SellRatePct` (the server's stall rate from its samples, or set before
  "Open" by a held stall prompt — the only source of market mode); the client sends
  `TankSell(uid)` and nothing else (no amounts, prices or slots); `TankEvent "Open"` only opens
  it, "Sold" / "Denied" answer a sale.
- **World tank** (`Workspace.TankWorld`, client-only: `DisplayFish_<base>_<slot>` models and the
  `Fx…` words on attachments of one invisible anchor part): TankWorldController (`GetFish`,
  `GetTag`, `GetSign`, `GetPierWord`, `IsBuilt`, `IsAlive`, `Stats` for tests and previews).
  It reads the slot attributes in the order the server writes them (fish fields → `State` →
  `Event` last; tools/builder/DESIGN.md «Tank slots at runtime»); they need
  `StreamingEnabled = false` (tools/build.luau).
- **Base badge / banner**: `HUD.Status.BaseBadge` (face "Swatch", `FlagSocket.Flag`, `Label`;
  `Lip.BackgroundColor3` = the base swatch's Lip) and `HUD.BaseBanner` (`Caption`, `NameLabel` +
  `NameLabelShadow`, `FlagSocket.Flag`): HudController only; never shown by other modules.
- **Home** (`HUD.RightButtons.HomeButton`: `Icon`, `Caption`, `Cooldown` veil with
  `CooldownText`, `Badge` — the hidden red «!» for the shop of stage 5: show it with
  `UiFx.badgeBob(HomeButton.Badge)`, hide with `UiFx.badgeHide`).
- **Toasts**: `NotifyController.Show(text, kind?, look?)` from any client module; kinds as in
  `UIConfig.ToastKinds` (`"Legendary"` / `"Mythic"` for server-wide rare-catch broadcasts; the
  server sends them as the Notify kind, one string «Who: what» that the client splits at the
  first ": " into two lines); `look = { swatch?, icon? }` overrides the colour/icon.
  No toast while the catch is on screen (the HUD has `CounterHold`, or `HUD.Fishing.CatchCard` is
  Visible); while `Minigame` or `BiteAlert` is Visible one toast shows — on phones none but
  danger (the rest queue); while a ghost (`FxMinigameWin` / `FxMinigameMiss`) plays or a hit word
  (`Minigame.FxFloat`) rises, none but danger on every screen; on phones none but danger while
  the own character holds a `HeldFish` (v3); keep those names and drive them through `Visible`.
- **Never cover the own fisher on a phone** (v3, WOW-1 / UIM-01…04): widgets that show during
  the cast, the bite, the fight and the trophy are placed with
  `Controllers.FishingLayout` (`fisherBox` — the own character with the rod and the held fish
  projected through the camera, padded 12 px, or `fallbackFisher` where it stands at the default
  camera; `avoid` — lower / slide aside; `dockSide` — a slot beside him; `topBand` — above him;
  `slamPivot` — where a slam from big grows from so even its first frame misses him;
  `clearOf` — a word over the panel kept off the status plates and the base flag: less rise, a
  small step aside or lower). On a tablet
  or a PC the minigame docks beside him too when at the bottom it would lie on him (r4).
  No Roblox hotbar (HudController: `SetCoreGuiEnabled(Backpack, false)`): the rod is taken with
  «ВЗЯТЬ» — offered wherever the rod is in the Backpack, with the hotbar's key 1 (and F / R2);
  a custom hotbar comes with the shop stage — keep the bottom band under the fisher's
  feet for the hint and «КЛЮЁТ!».
- **Off-screen trophy chip**: `FishingFxController.OtherTrophy` (Signal: `player, basePosition,
  rarity`) fires on every client but the catcher's when a Legendary / Mythic pillar goes up;
  NotifyController clones `HUD.TrophyPointer` (children `Body` — a round sim disc with an
  `IconSocket.Icon` —, `Tip`, `BaseRing.Stroke`) as «TrophyChip» for
  `FishingConfig.Fx.PillarTimeOther[rarity]` s. Stage 3 can reuse the signal (e.g. a theft alarm
  pointer) and the template.
- **Catch card time**: `UIConfig.CatchCardTime[rarity]` (seconds of auto-close).
- **Stage 4 widgets** (built hidden in wave 0, docs/stage4_design.md §6.1; one owner each):
  `RightButtons.DefenceButton` (`Icon`, `Caption`, `Badge`, `Cooldown.Drain`, `CooldownText`; the
  column's 3rd square, Guard) and `Status.BaseBadge.ShieldChip` (`Icon`, `Label`) —
  DefenceController; `HUD.TheftBar` (`Plate`, `Icon.Icon`, `Title`, `Time`, `Sub`,
  `Bar.{Track, Fill}`, `DogChip`) and `HUD.TheftTitle` (`Title`, `Sub`) — TheftController;
  `HUD.TheftAlert` (`Plate`, `Icon.Icon`, `Text.{Title, Sub}`, `Buttons.{Shield, Home}`,
  `Compact.{Label, Shield, Home}`) — AlertController; `HUD.DefencePanel` on the sheet shell
  (`Panel.Header.{Icon, Title, Money}`, `Cards.{ShieldCard, DogCard, AlarmCard, LockCard}` each
  `Icon.Emoji`, `Name` — reach it with `FindFirstChild("Name")` —, `Effect`, `State`,
  `Buy.{Label, Price}`) — DefenceController + `Controllers/Sheet`. Their numbers:
  `UIConfig.Theft`; their texts: `StealConfig.Texts` / `DefenceConfig.Texts`.
- **Stage 4 placement rules** (keep them when you add a widget):
  - **The thief's bar and «ДОБЫЧА!» stay in the bottom band** (§6.4 rev. 3 of the design):
    `HUD.TheftBar` / `TheftTitle` centred between the thumbstick and Jump, ≥ 16 px from them and
    the screen edge, never in the upper middle where the robbed display and the fish on the
    thief's head are. While the HUD has `Stealing`, the status stack is hidden and
    `NotifyController.Reserve("thief", …)` holds the whole column (no toast, no trophy chip on
    phones) — a new widget for the thief goes into the bottom band too.
  - **The alert plate sits at the top of the toast column**: `NotifyController.Reserve("alert",
    px)` moves the toasts below it (`Offset(key)` — the bands before `key` in `RESERVE_ORDER`,
    asked before it reserves too, so the thief's whole-column «thief» band never pushes it down;
    `Reserved()`), inside the column's px width
    (≤ `UIConfig.Theft.Width` × W and `WidthMax`); on tablets and PCs the toasts wait for the
    alert's end, on phones the pill keeps 16 px from the fisher and every widget listed above.
  - **The alert's layers take no layout** (edge pulse, «ДОМОЙ!» / «ЩИТ!» glow, the pier word,
    pings): they show from the first frame and never move another widget; only the plate (or the
    pill) needs a place. Never add a full-screen flash: the edge pulse is ≤ `Theft.Edge.Alpha` and
    ≤ 3 Hz.
  - **The alert outranks the catch card**: `FishingController.HurryCard()` closes the card by its
    normal path; the plate waits for the card, `CounterHold` and an open sheet, never draws over
    them, and never takes the minigame's input (its input is only the action button).
  - **Guard is the defence colour**: «ЗАЩИТА», «ЩИТ», the shield chip and the shield card use
    the `Guard` token; danger (the thief, the alert, «ЩИТ!» during an alert) stays `Berry`.
  - **Toasts enter and leave inside their column** (C-31): a toast drops in from no higher than
    the column's free top (`ENTER_DROP` capped at its slot's scale above the reserved bands) and
    rises out by ≤ `LEAVE_RISE` px within the column, so a pop-in never crosses `HUD.Status`.

### 6.6 Rules for the next agents

- Build new widgets with Theme (`sim` / `glass` / `simButton` / `plate` / `badge` / `stat` /
  `title` / `label` / `icon` / `socket`) and animate with UiFx — no hand-rolled colours or tweens;
  new colours go into UIConfig, the shape numbers into `UIConfig.Sim`, timings into
  `UIConfig.Motion`. Keep the surface names (Lip / Face / Fill / Rim / Shine) so `setCandy`,
  `press`, `rimFlash` and the tests keep working. **Smooth surfaces only** (no side bands,
  nothing raised on a face): the LEGO look belongs to the map. The sim primitives are the whole
  builder API — there are no older aliases to fall back on.
- Buttons: a saturated gradient, the thick outline in the dark shade of the SAME hue (never black,
  never a random colour), the light rim; panels that are not buttons use `PlateRadius`; secondary
  info goes on glass. Big numbers and titles go WITHOUT a panel (`stat`, `title`).
- CAPS for badges, buttons, banners, chips and titles through `TextUtil.upper` (Cyrillic);
  sentence case for hints and plain toasts. Numbers in italic. Icons outlined; overhanging a
  plate's left end is the default for plates.
- Give every label a text tier (`Tier = …`) and a box at least that tall; no `MinTextSize` below 12.
- Effects that run right after joining (the base banner, the badge) are timer-only (`confettiPop`,
  no sparkles left behind after ~2.5 s): client tests take their idle baselines soon after a
  player joins.
- The camera's FieldOfView belongs to `UiFx.fovPunch`; screen edges to `edgeVignette`; on touch
  devices rays come without halo quads and capped (`maxPx`) — mind the fill rate on phones.
- Bind `UiFx.press` once per button at Start (its connections live as long as the HUD); a press
  grows a button by at most `Motion.Press.MaxGrow` px — keep ≥ 16 px from the Jump button and
  other CoreGui buttons at rest anyway.
- **Idle and ambient effects must be timer-based** (breathe, bob, sway, wobbleLoop / badgeBob,
  shineLoop, pulse, glowRing loop, rays, sparkles): client tests compare connection counts at two
  moments (stage2_client "unequip and respawn…", "leaks…", hud_style "idle HUD") and check
  `UiFx.activeJobs() == 0` when idle. Frame effects (confetti, burst, countUp, rainbow, timerBar,
  flyTo, trail) are for events and must be stopped — keep their stop function in the widget's
  Trove; a rainbow left running on a hidden card is a leak.
- Inside a UIListLayout, Position is ignored and a UIScale re-flows the siblings (the scale origin
  is the AnchorPoint): prefer wiggle / bump there, never shake; `bob` moves the AnchorPoint and is
  safe there.
- Keep names: animate by adding children (FxScale, FxRing, FxRays, FxFloat, FxMorph, FxSwap,
  FxRingTimer… are created and removed by UiFx), never by renaming or re-parenting contract
  widgets.
- Recipes. Catch card (FishingController): `rays(raysHolder, {colors = UIConfig.Rarity[r].Rays,
  maxPx = …})` in a transparent holder behind the card (its ring placed in pixels by
  `CatchFx.aimRays`; the holder clips them beside the fisher) and `rays:settle()` after the last beat,
  `popIn(card, {rotate = -6})`, `confetti(hud, {count = …, origin = the held fish on screen})`,
  a count-up with `CatchFx.money` («$0 → $58», `TankRules.FormatMoney`), `stamp(mutationBadge)`, Legendary/Mythic:
  `shockwave(hud, origin)` + `cameraShake()` + `fovPunch()` at the landing (never a full-screen
  flash); on close `flyTo(hud, start, «САДОК» (or `Wallet.Money` with a 💵 for a fish sold on the
  spot), {onArrive = clear CounterHold and CounterIncoming})`
  from a fixed start point (an invisible `FxFlyFrom` frame placed once). Action button: a round
  `simButton` anchored at its centre, `recolor` + `punch` per state (capped by its `GrowMax`),
  `morphFlash` on important looks, `glowRing(button, {loop = true})` while it matters (its scale
  capped so it keeps 16 px to Jump), `breathe` + `shineLoop` + `wobbleLoop(icon)` when idle, one
  capped ring on tap, `ringTimer` for a timed choice (the bite). A widget that leaves while its state is torn
  down (the bite alert) leaves as a ghost (`ghostOf` + `popOut` / drift + `fadeOut`). A new notification on a button: `Theme.badge` +
  `UiFx.badgeBob`.
