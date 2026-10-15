# UI & FX style guide — «Кирпичики» (UI v3 Brick; motion and FX from v1/v2)

The user's briefs: «мега красивый интерфейс и мега красивые пёстрые анимации, чтобы все были в
шоке» (v1/v2) and «текстурки типа лего как в Steal a Brainrot … как-то улучши интерфейс» (v3). The
world is a studded toy-brick world (tools/builder/Studs.luau, DESIGN.md); the **interface is made
of the same toy bricks** — chunky studded bricks and smooth tiles in bright brick colours, heavy
CAPS lettering with thick near-black outlines, flat emoji stickers. The colour explodes in the
effects (§2), like the top Roblox simulators (Steal a Brainrot, Pet Simulator 99, Grow a Garden).
Never write «LEGO» in the game or show its logo: in Russian copy the bricks are «кирпичики» /
«блоки».

Everything here is built from plain GUI instances (Frame, TextLabel/TextButton, UICorner, UIStroke,
UIGradient, UIScale, ViewportFrame) and built-in particle/sound content — **no uploaded images or
asset ids** (we cannot upload). Emoji are our icons (in game they are flat Twemoji).

## 1. Look

**Bricks.** A chrome widget is a toy brick seen from the front (`Theme.brick`, the anatomy in §6.2):

- a **side band** (`Lip`): the bottom 16 % of the height in the colour's `Lip` (≈ 0.6 of its value);
- a **face** with a light **cap** on top (the brick's top surface: Top lightened 30 % in the top
  12 %, then Top → Bottom) and a small white **glint** (`Spec`) at its top left — no glossy band;
- **studs** on the top edge (front view: a rounded bump in the brick's colour, lit from the left,
  Ink outline; the brick's own outline cuts their bottoms off): 1 per ≈ 1 brick height of width,
  at most 8 (the badge 4, the counter 3, Home 2, the base banner 6, the flag tile 1);
- a thick **Ink outline** around the whole shape: `Ink` #15171C (neutral near-black), 4 px at 720
  (2.5 px on a phone), corners 0.16 of the short side.

**Tiles** (`Theme.tile`) are smooth bricks: no studs, a 12 % side band, corners 0.2 — toasts,
hints, chips. **Rarer = a bigger brick**: Legendary / Mythic broadcast toasts grow studs (Mythic's
in rainbow colours). Seen from above (plates: the minigame baseplate, the card, pips — UI v4), a
stud is a round disc with a lit cap (`Theme.topStud` / `studRow`, no outline); the action button
becomes a **round plate** with a raised centre stud (`Theme.roundPlate`). Round shapes only for
that, studs, pips and sockets — **no pills** in new widgets (the fishing widgets keep their
v1/v2 candies until UI v4 rebuilds them; they already take the palette, font and outlines).

**Colours.** Bright toy-brick colours under the old token names (controllers recolour with
`UiFx.setCandy(root, token)`; Top → Bottom, Lip = side band):

| token | brick colour | use | top | bottom | side band |
|---|---|---|---|---|---|
| `Sky` | blue | cast / primary action, info | #4FA3FF | #0A6CD8 | #053E85 |
| `Sun` | orange | bite / alert | #FFB347 | #FF7A00 | #A34A00 |
| `Leaf` | green | reel / success | #7EDB5A | #2FA82F | #1A621C |
| `Berry` | red | stop / danger / miss | #FF4A3D | #E3000B | #8E0008 |
| `Grape` | purple | special / epic | #C08CF0 | #8E44C6 | #522577 |
| `Gold` | yellow | money, the catch counter, legendary | #FFE45C | #FFC20E | #B07A00 |
| `Night` | dark stone | panels, tracks, hints | #5B6168 | #3E4349 | #24282C |
| `Cream` | white plate | cards, flag tiles, sockets | #FFFFFF | #E6E9EC | #A9AFB5 |
| `Slate` | light grey | disabled / waiting, no base | #C9CED3 | #A0A5A9 | #6C7176 |
| `Mint` | azure | Home (never confused with the green «ЛОВИ!») | #6FE0F5 | #1FA9D6 | #0E6585 |
| `Water` | teal | waiting for a bite | #67D9E3 | #1593A6 | #0A5763 |

Base colours are clean swatches too (`UIConfig.BaseSwatches`, by the BaseConfig colour Id): Red =
Berry, Blue = Sky, Yellow = Gold, Purple = Grape, Orange = Sun, Cyan = Mint (azure), Pink
#FF7EB6 → #E8448F, Green (emerald) #5FE3A0 → #12A05E; any other colour goes through
`UIConfig.swatchFor(color)` (lighter top, saturated bottom, side band ≈ 0.62 of the bottom).

Rarity: Common light grey `#E2E6EA→#A0A5A9`, Rare blue `#4FA3FF→#0A6CD8`, Epic purple
`#C08CF0→#8E44C6`, Legendary yellow → orange `#FFE45C→#FF9A00`, Mythic = an **animated rainbow**
(UIGradient with 6+ hue keypoints whose Offset/Rotation moves; studs included). Mutation badges:
Gold (gold gradient + sparkles), Neon (#4DFFF0→#19C2FF, glowing pulse), Rainbow (animated rainbow).
The e2e bot's filled pip colour `UIConfig.Fishing.PipDone` rgb(64, 200, 96) never changes.

**Text.** One family: Nunito **Heavy** (Black 900 — `Theme.FONT`, `UiFx` uses the same; Cyrillic;
never FredokaOne / LuckiestGuy / Bangers / DenkOne / TitilliumWeb: no Cyrillic). White with a
thick Ink outline (a UIStroke "Outline", Contextual). **CAPS voice** for badges, buttons, banners,
chips and titles («ЛАЗУРНАЯ БАЗА», «ДОМОЙ», «ЗАБРОСИТЬ», «РЕДКАЯ»; Cyrillic capitals through
`TextUtil.upper` — `string.upper` knows only Latin); sentence case for hints, plain toasts and
«Тапни — забрать!». Outlines at 720 px (`UiFx.fitStrokes` scales them; never under
`UIConfig.Fx.TextStrokeMin` = 2.5 px):

| what | outline at 720 | on a 390-px phone |
|---|---|---|
| Small tier | 3 | 2.5 |
| Body tier | 3.5 | 2.5 |
| Button tier | 4 | 2.5 |
| Title tier | 4.5 | 3 |
| display text (the base banner name, cooldown digits, the counter) | 4.5–8 | 3–5 |
| shapes (bricks, tiles, sockets) | 4 | 2.5 |
| legacy candies (the fishing widgets until UI v4 rebuilds them) | 3 | 2 |
| studs | 3 | 2 |

A tiered label gets at least its tier's outline (`Theme.label`); dark text on a white tile (the
key chip, the weight chip, «Тапни — забрать!») goes without (`Outline = false` /
`TextStrokeTransparency = 1`). Never below 12 px on a phone (UITextSizeConstraint).

**Type scale.** Text that means the same thing has the same size on one screen. Four tiers
(`UIConfig.Type`, Roblox TextSize = line height in px on a 390 px tall screen):

| tier | px | used for |
|---|---|---|
| `Title` | 22 | base badge, minigame title, rarity banner, fish name |
| `Button` | 18 | action caption, «СМОТАТЬ», «ДОМОЙ», Legendary/Mythic broadcasts |
| `Body` | 16 | hints, Help, toasts, «Тапни — забрать!» |
| `Small` | 14 | chips (weight) |

A label gets its tier with `Theme.label(…, { Tier = "Body" })` (attribute `TextTier`);
`UiFx.fitText(hud)` (HudController) sets Max = tier × clamp(H / 390, 1, 1.6), Min = Max − 2 for
every tiered label, also ones cloned later. Give the box at least that height; long copy is
shortened (or the widget grows a line), never shrunk below its tier. Display text (the giant
rarity title, the base banner name, cooldown digits, the catch counter's number, the catch card's
price — up to 1.4 × Title, never under Button − 2) is box-driven, not tiered. CAPS Cyrillic is
10–20 % wider: check «ФИОЛЕТОВАЯ БАЗА», «ЗАБРОСИТЬ», «МИФИЧЕСКАЯ» on `phone_small`.

**Icons.** Emoji in their own TextLabel, **upright** (Rotation 0; only stamps — «НОВИНКА!», a
mutation — and the base banner's flag tilt), no Ink outline (in game they are flat Twemoji, drawn
with Roblox's content/fonts/TwemojiMozilla.ttf — the GUI previews draw the same font). A **sticker**:
an icon in a white 1x1 round tile (`Theme.socket`: white disc, Ink outline, a thin inner rim), or
a free-standing one with a white rim (`Theme.icon(…, { Sticker = true })`: a white Contextual
UIStroke around the emoji's shape — the counter's 🐟, Home's 🏠). 🎣 🐟 🏠 💰 ⭐ ✨ ❗ 💪 🔥 🌈 👑.

**Hierarchy.** One idle accent per screen: only the action button shines or breathes; the chrome
stays calm (the badge shines only when the base arrives, Home when its cooldown ends), and the
badge is quieter than the counter (smaller text, no idle motion).

## 2. Motion (the "juice")

All motion comes from the client library `ReplicatedStorage.Shared.UiFx` (one place, consistent
timing). Every effect must clean itself up (Destroy temporary instances, cancel tweens) and accept a
Trove or return a cleanup function.

| effect | how | timing |
|---|---|---|
| press | UIScale 1→0.88 (Quad Out) on press, →1.0 Back Out on release | 0.06 / 0.25 s |
| pop-in | UIScale 0→1.08→1 (Back Out), optional rotation −6°→0 | 0.3 s |
| slam | UIScale 2.2→1 (Back Out) + small shake | 0.35 s |
| pulse | UIScale 1↔1.08 (Sine InOut, repeat) | 0.8 s period |
| wiggle | Rotation ±6° (Sine, 3 swings) | 0.4 s |
| shake | Position jitter ±1.5 % decaying | 0.25 s |
| shine | white diagonal gradient band (Transparency sequence 1→0.4→1) sweeping Offset −1→1 across a button/card | 0.6 s, every 3–4 s on idle main buttons |
| glow ring | a copy of the round shape behind it, scale 1→1.5, transparency 0.3→1 | 0.6 s, repeat while important; stop fades live rings in 0.1 s |
| rays | sunburst of 8–16 thin rotated bars in alternating rarity colours, growing from the centre (Quad Out, no overshoot), slowly rotating (≈20°/s; two rings turn opposite ways), behind titles and the catch card; on touch: no halo quads, no breathing, size capped (`maxPx`); `settle()` after the reveal (+0.25 transparency, half the spin); with a `hole` the middle stays empty (rays around the landed fish, not over it) | while shown |
| confetti | 30–60 small Frames (squares/strips, random vivid colours, rotation), launched up/out then falling with gravity and spin, fading in the last 30 % | 1.6–2.2 s |
| sparkles | ✨ / ⭐ labels popping in/out at random spots around an element | while shown |
| float text | «ОТЛИЧНО!», «+1 🐟», «МИМО!» rise 8 % and fade, slight rotation | 0.8 s |
| count-up | number ticks from 0 to the value (Quad Out) | 0.6–1.0 s |
| rainbow | UIGradient colour keypoints shifted every frame (hue cycle), or Rotation spin | continuous while shown |
| flash | full-screen white/rarity-coloured Frame 0.6→1 transparency (`flashBig` 0.12 exists but is not used: never a near-solid screen on a catch landing — a phone player loses the fish) | 0.25 s; ≤ 3 per second |
| shockwave | the landing hit at a point: a thick rarity ring + a thin white one expand from it, a soft disc fades faster; the middle stays clear, nothing covers the screen | 0.45 s |
| edge vignette | 4 edge bands in a colour (or a gradient), fading towards the centre; static, pulsing (≥ 0.34 s period) or one-shot | tension, bite, perfect hit |
| FOV punch | the camera zooms in a few degrees and back (all punches summed, capped at −8°); with `easeIn` a slow wind-up (Sine In) — e.g. a small zoom-out before a Legendary/Mythic landing | 0.08 s in, 0.35 s out |
| sounds | pooled built-in sounds with a pitch; rarity arpeggio (Common 1 note … Legendary 4, Mythic 7) | events |

Easing defaults: Back Out for appearing, Quad In for leaving, Sine for loops. Nothing linear except
timers. Stagger groups by 0.03–0.06 s.

## 3. Where it is used

- **HUD chrome** (tools/builder/gui/Hud.luau, HudController, NotifyController — all bricks, §1):
  base badge (a brick in the base swatch with 4 studs, a white 1x1 flag tile with one stud over
  its left end, «ЛАЗУРНАЯ БАЗА» in CAPS at the Title tier; «ИЩЕМ БАЗУ…» / «ЖДЁМ БАЗУ…» on light
  grey; shines only when the base arrives); the base banner (first assignment: a big brick with 6
  studs, «ТВОЯ БАЗА» / «ЛАЗУРНАЯ!» across the centre in the base swatch, the flag tile waving,
  rays, confetti, a fanfare; after 2 s it shrinks into the badge, which bumps); catch counter (a
  yellow 1x3 brick «🐟 12» like a coin display: the 🐟 sticker over its left end, the number big —
  box-driven, about Title; bump + «+N» + a higher tick when the fish arrives — held while the HUD
  has `CounterHold`); Home button (a square azure 2x2 brick with 2 studs, 🏠 sticker and «ДОМОЙ»
  on its face, 🏠 wiggle on press; cooldown: draining veil, digits on the face, «ЖДИ» over the
  veil, the house fades; one shine when ready); toasts (smooth tiles by kind with the icon in a
  white round tile, slide-down + bounce, shine; a column right under the status stack — 3 on a PC (clear of the chat window), 1
  on a tablet or a phone (above the avatar's head); none while the catch is on screen, 1 over
  the bite / minigame (on phones none but danger), none but danger while a hit word or a minigame
  ghost («МИМО!», «ПОЙМАНА!») rises into the column, the rest queue — a toast pushed off in the
  first half of its life comes back; Legendary (a yellow brick, 🌟) and Mythic (rainbow, 🌈)
  broadcasts are bricks with studs (rarer = bigger; Mythic's studs in rainbow colours) in two
  lines — who (Small) over what (up to Title, the rarity word in capitals, light-gold /
  running-rainbow letters), Mythic adds one thin rainbow edge pulse; leaving: rise + fade, ≥ 0.7 s apart).
  Someone else's Legendary / Mythic pillar off-screen (behind the camera or past the frame's
  edge): a small chip at that screen edge (HUD.TrophyPointer → «TrophyChip», ≈ 46 px, y 0.38 of
  the HUD, ≥ 16 px from the edge) — 🌟 / 🌈 in a white tile on a round yellow / rainbow brick ringed in the catcher's
  base colour, its tip nudging 6 px towards the edge — for the pillar's life; gone while the
  pillar is on screen; on phones hidden during the own bite / minigame / catch (the toast rule).
  Only the primary CTA idles (shine + breathing); the chrome stays calm.
- **Fishing UI** (tools/builder/gui/Fishing.luau, FishingController): the action button is the star —
  a big round candy button (ActionArea, 0.66 of the HUD height, max 320 x 240) whose gradient, icon and
  caption ribbon change by state (ЗАБРОСИТЬ 🎣 → ЖДЁМ… with a bobbing float and 1–2 nibbles «?» →
  ПОДСЕЧЬ! «!» → ЛОВИ! 🎯; Slate ⏳ while waiting on the server, КУДА ИДТИ? 🧭 far from the spot — it
  shows the way, never scolds: a calm 💡 hint, the compass turns, the guide beam flares; ВЗЯТЬ
  in gold at the spot; a dim frozen ЖДЁМ… during the catch until the card is fully shown, then
  ЗАБРАТЬ! 👍 in Leaf with white rings — it closes the card), glow rings while it matters, shine on idle, press squash, ripple on tap; a key
  chip («F» / «R2») on its shoulder without touch. «СМОТАТЬ» (≥ 44 px, ≥ 22 px above the circle)
  only while waiting: it pops out once a fish bites. Bite alert: «КЛЮЁТ!» slams in with a sun flash and a
  FOV punch, sun edge glow, one BITE_BEAT for the plate, the button and the swinging «!» glyphs, a
  gradient countdown bar (green→yellow→red); on touch the plate is a tap pad, a 👆 helps the first
  two bites, and the plate gets a little lower (or moves aside) when it would hide the own diving
  bobber. Minigame: candy track, glossy green zone with a rider by rarity (🐟 🐠 🐡 🦈 🐉; Legendary+
  bigger and glowing) and a glow pulse, needle ▼ with two fading ghost copies (under the zone), a
  light Rare rim, Epic+ outline/aura in the rarity colours, Legendary/Mythic slam the giant rarity
  word over the panel once (the first hit / miss / win word knocks it away: it swells and fades in
  0.12 s — never two words stacked); on phones the panel stands beside the own bobber when it would cover
  it; the hit is shown at once (the needle freezes gold, sparks, rising pitch) with
  «ОТЛИЧНО!» → «СУПЕР!» → «МЕГА!» or «ИДЕАЛЬНО!» (within 25 % of the zone centre), pip turns into a
  ⭐; on touch the panel itself is a tap pad and a 👆 cue helps the first games; on miss / timeout a
  copy (FxMinigameMiss) blushes, shakes and says «МИМО!» / «ВРЕМЯ!», and is gone before the reason
  hint springs up. Hint: a pill in the kind colour (💡 / ⚠️ / 🚨 in a white socket), up to two lines,
  pops up from a few px below (the hotbar is right under it). The catch (UI v2) shows the world
  first: the winning tap freezes the needle gold where it was tapped (gold zone flash, a glow ring, a
  small bump, a higher pop) until the server answers (≤ 1.5 s); on "Caught" the minigame plays its
  win (FxMinigameWin: ⭐, gold zone, the needle where it was tapped, sparks) and sinks away early, and
  «ПОЙМАНА!» slams in (2.4 → 1, tilted, ≈ 0.17 of the HUD height, in the rarity colours — Mythic a
  sweeping rainbow — with a glow ring) left of the character, never over the leap, and is gone
  ≈ 0.2 s before the landing (a quiet beat before the shockwave); the status badge and the counter
  fade out, the button freezes; Epic+ get a narrow edge frame (0.13 of the height) that builds
  0.85 → 0.5 alpha into the landing (Quad In) and cuts off on it — Mythic's is a light rainbow
  cycling around the frame —, Legendary/Mythic an accelerating heartbeat (sound only) and a slight
  FOV wind-up while the fish leaps. On the landing (`FishingFxController.OwnFishLanded`) **a crisp
  burst at the fish, never a wash** (v3): a thin shockwave ring (`UiFx.shockwave`, `CLIMAX.Shock`:
  no glowing middle, ≈ 0.34 s) and sparks from the fish's point — no edge flash —, in the world a
  small white pop, a star of thin rarity rays and a thin halo at the fish (the own Legendary/Mythic
  pillar only rises 0.3 s later, with a thin core), shake and FOV punch, confetti; for Epic+ the
  rarity rays start around the fish (empty middle; during the title stage thin spokes, more
  transparent than the card's — `CLIMAX.TitleRays` — so no yellow/white glow piles up around the
  fish) with the giant rarity title (TitleSlam, 0.24 of the HUD height within the side limits;
  white → rarity → shade fill, a thick outline; Legendary/Mythic letter by letter, each letter
  starts its wave as it lands; a white shine sweeps the word right behind the letters) and, once
  the shockwave is gone (+0.55 s), a light full-screen dim (the card's dim + 0.2) so rays and
  letters pop — a title stage of 0.6 / 0.9 / 1.0 s (Epic / Legendary / Mythic; Common 0.35 and
  Rare 0.4 let the landing pop and halo play before the card) — then the card is born at the fish
  and settles (position Quint Out,
  no overshoot; the rays follow it): a landscape trophy card on phones (fish left, name and chips
  right; centred — on the smallest phone above the action button, a side limit only counts when its
  obstacle is level with the card), the 380 x 384 square elsewhere; Legendary 1.05x and Mythic 1.1x
  the size (on phones the free space is the Mythic's), a dim around it (letterbox bars on phones;
  none for Common). The rarity shows on the card itself: small rays behind the fish; Epic+ a live
  rim (Epic Grape pulse, Legendary gold sweep, Mythic spinning rainbow — with a mutation it moves
  to the banner's outline and the mutation keeps the card's), Legendary/Mythic a face tinted
  towards the rarity (Mythic: a slow pastel rainbow). The name is born with the card (it slides
  in from the right while the card settles, Quint Out — no blank right half). Then its beats, one
  at a time — Common/Rare (fished dozens of times) ≥ 0.2 s apart, Epic+ ≥ 0.27 s —, each with its
  own motion: rarity (the title flies into the banner and the banner grows out of it at 70 % of the
  flight while the title fades out in 0.08 s and the banner's label fades in — never two readable
  words; without a title the banner unrolls from the middle, Quint Out) → «НОВИНКА!» (a stamp — only stamps use
  Back Out) → chips (rise, Quad Out, the price 0.08 s later) → price count-up (a soft ease-out
  that keeps running into the landing: 0.15 s before it ≤ ~92 %) and landing (the chip squashes
  1.25 × 0.85 and springs back, Elastic Out; the price itself is the card's biggest number; 0.12 s
  later «+N 💰» flies OUT of the chip — Back Out to the free space right of the card, never over
  the price or «×N», smaller where tight, over the weight row only as a last resort — rises and
  fades, the chip bumps as its source — Rare+, a new species or a mutation; Legendary/Mythic 💰
  rain beside the card, behind it, and a confetti volley; Mythic a rim flare, rainbow sparks and a
  little shake) → mutation (the base price only ticks and breathes one beat; corner stamp, «×N»,
  recount — the party goes to the full price —, the outline in its colours) → the close hint
  «Тапни — забрать!» (Body tier, breathing 0 ↔ 0.15) and the action button's «ЗАБРАТЬ!» (Leaf 👍,
  white halo and rings); then everything calms down and a Mythic card breathes (grows upward, its
  bottom stays). A NEW species of a Common/Rare fish gets a small fanfare (the first catch of a
  new player is usually one): a light dim, brighter rays with gold and green, sparks + a handful
  of confetti + a ping at «НОВИНКА!», a «+N 💰»; a known Common stays calm. On phones the card is
  never shorter than 165 px (the smallest phone's Common card). Mythic's confetti comes in three
  volleys (landing, +1 s, the price) under the touch cap. A tap on the card skips to the end, a tap
  at least 0.6 s later closes; the action button (F / R2, the rod) never skips — it only closes
  the settled card, and not while it is being mashed (< 0.3 s since the previous press). The card
  closes by itself after `UIConfig.CatchCardTime` (at least 0.6 s after its last beat). Closing:
  the card itself is the projectile — it flies into the counter shrinking to a speck (the first
  catch: the counter pops in with «🐟 0»; the card aims at its slot in the Status list), a 🐟
  with ★ in the rarity colours leaves beside it and they land together (tap → «+1» ≈ 0.35 s; the
  counter holds its number meanwhile and greets the fish in the rarity colour); right after the
  «+1» the trophy over the head flashes once more (`FishingFxController.ReplayOwnTrophy`; the own
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
  (rarity, name, mutation, price; sized in studs + pixels; above the fish for others, popping in
  at the landing; beside it — to the right — for your own, hidden while the catch is on screen:
  under the title it would repeat the word, by the card show the final price early) and the
  rarity aura around the held fish for `FishingRules.HoldFishTime(rarity)` s (≈ 3 s longer than the
  catch card, so your own trophy is still there when the card closes; then, after the counter's
  «+1», `ReplayOwnTrophy` pops it once more: ball, halo, sparks, the own nameplate pops in (no
  replay — 0.5 s after the counter is released), a chime, a short pillar for Legendary/Mythic — on
  short screens (< 500 px) no pillar and a 0.7× halo, so nothing rings the counter; once the
  card has opened the own camera offset rises 0.6 stud — hidden by the card — so the trophy and
  its plate clear the counter afterwards). **The held fish is alive** on every client in range
  (FishLife): it bobs, wags its tail and every 1.3–2.2 s flops (the body bends from 42 % of its
  length, plus a small hop and roll), a stronger flop on the replay; it never leaves its spot or
  changes size — the same trophy for the title, the card and the replay —, and the nameplate only
  drifts gently, never shakes;
  Legendary/Mythic: a light pillar (narrower on your own screen; for everyone else wider with
  distance — ≥ 25 px from the neighbouring pier —, taller with distance — 40 + d / 2 studs, a beam
  to the sky from any pier —, starting above the catcher's nameplate when near, and longer,
  `Fx.PillarTimeOther`; their broadcast toast lands with it, `FishingFxController.OtherTrophy`
  points the HUD chip at it) and a confetti burst, seen by everyone. A lost fish: the line flashes red and goes slack, the bobber pops
  up, a splash and a tail flick away, the shadow flees and fades.
- **The fisher's body** (FisherAnimController + FisherRig / FisherPoses / FisherRod; every client
  animates every fisher within 150 studs, writing joint.Transform in PreSimulation over the default
  Animate pose): a wind-up with the bobber hanging at the rod tip until `CastTime` (= cast +
  `FishingConfig.CastWindUp` 0.3 s, so all clients see it), the throw exactly when the bobber leaves
  the tip, waiting sway + looking at the bobber, bite startle and tip jerks with the bobber's dips,
  a strike, the reel fight (braced legs, left-hand crank at 2.2 Hz, body and rod swung in phase
  with the bobber's thrashing), catch (yank, look up at the leap, both hands up under the fish over
  the head, a hop and «pumps»; a held trophy is carried overhead while walking), loss (slump, head
  shake). The rod bends towards the line under load and whips on the cast (a spring, ≈6 Hz); its
  TipAttachment moves with the bend, so the line and the flying bobber follow the bent tip. Poses
  and timings: FisherPoses (key-pose sheets: tools/preview/pose_dump.luau + pose_sheet.py). While
  walking, torso and head go back to the normal animation at once (arms stay posed); every
  transition is a crossfade, nothing pops. Rules: no uploaded / Studio-registered animations, no
  C0 writes (AnimationConstraint rigs), no per-frame work when nobody fishes nearby.

## 4. Budgets (phones first)

- At most ~60 temporary GUI objects alive at once from effects (confetti 40 max on phones, 60 on PC);
  everything destroyed when done. No RenderStepped/Heartbeat connection while nothing animates.
- World: at most 2 ParticleEmitters active per player at a time; parts for ripples/pillars are
  client-side, CanCollide/CanQuery/CanTouch false, CastShadow false, destroyed after use.
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

## 6. API (UI v1 foundation, v2 additions, v3 bricks)

Where things live:

| what | file | side |
|---|---|---|
| colours: palette tokens, rarity/mutation styles, toast kinds, confetti mixes, FX limits | `src/ReplicatedStorage/Shared/Config/UIConfig.luau` (pure: Color3 only) | both |
| the brick's proportions (`UIConfig.Brick`) | same file — builder and client read the same numbers | both |
| builder helpers (bricks, tiles, studs, candies, labels, icons, gradients) | `tools/builder/gui/Theme.luau` (reads UIConfig via `U.loadPure`) | Lune |
| motion library (+ brick recolouring, runtime studs) | `src/ReplicatedStorage/Shared/UiFx.luau` | client |
| CAPS for Cyrillic | `src/ReplicatedStorage/Shared/TextUtil.luau` (`TextUtil.upper`) | both |
| reference implementation | `gui/Hud.luau` + `HudController` + `NotifyController` | both |
| tests | `tests/ui_bricks.test.luau` (Theme kit, no sim), `tests/uifx.test.luau`, `tests/hud_style.test.luau` | Lune / sim |

### 6.1 UIConfig (one source of colours)

`Ink`, `White`; `Palette.<Sky|Sun|Leaf|Berry|Grape|Gold|Night|Cream|Slate|Mint|Water>` =
`{ Top, Bottom, Lip }` (toy-brick colours, §1; Slate = disabled / waiting; Lip = the side band);
`Rarity.<Common|Rare|Epic|Legendary|Mythic>` = `{ Top, Bottom, Lip, Rainbow, Rays = {…},
Confetti = {…}, ConfettiCount, Flash }`; `Mutations.<Gold|Neon|Rainbow>` = `{ Top, Bottom, Lip, Icon,
Effect = "sparkles"|"pulse"|"rainbow" }`; `Rainbow` (7 hues), `Confetti` (vivid mix);
`ToastKinds.<info|success|warning|danger|base|Legendary|Mythic>` = `{ Token, Icon, Rainbow?, Big?,
Life?, Priority? }` (danger icon 🚨; unknown kinds render as info); `KindColors` (flat colour per
kind = palette Bottom); `NoBaseColor`; `BaseSwatches.<Id>` and `swatchFor(color) -> swatch` (base
colours, §1); `Type = { Title = 22, Button = 18, Body = 16, Small = 14 }`, `TypeHeight = 390`,
`TypeMaxScale = 1.6` (§1); `CatchCardTime.<rarity>` = 2.2 / 2.8 / 3.4 / 4.2 / 5.1 s (client-only
auto-close of the catch card; Legendary/Mythic trimmed by their longer title stage); `ToastDuration`,
`MaxToasts = 3`, `MaxToastsTouch = 2` (tablet), `MaxToastsPhone = 1`, `ToastGap = 0.7`;
`Fishing = { PipDone (64,200,96 — the e2e bot looks for it), TrackBottom,
PipShade, NeedleShade, Muted, Guide, ZoneGlow, TimeBar = {cool, Sun, Berry} }` (fishing colours
outside the palette); `Fx = { ConfettiMaxTouch = 40, ConfettiMax = 60, ShineInterval,
FlashMinInterval = 0.34, StrokeHeight = 720, TextStrokeMin = 2.5, FovPunchMax = 8, SoundPool = 4 }`;
`Brick = { Lip 0.16, TileLip 0.12, Radius 0.16, TileRadius 0.2, CapLight 0.3, CapStop 0.12, StudW 0.56,
StudH 0.34, StudShow 0.74, StudLight 0.45, StudShade 0.25, TopLight 0.4, TopShade 0.12, Spec*,
StudStroke 3, MaxStuds 8 }` (§6.2; tune the look here, both sides follow).
FishConfig's rarity/mutation `Color`s stay the flat colours the stage-2 tests check; use
`UIConfig.Rarity` / `Mutations` for gradients and FX.

### 6.2 The brick and the candy (structure contract shared by Theme and UiFx)

A **brick** (`Theme.brick` / `Theme.tile` / `Theme.roundPlate`; UI v3):

```
<Root>       any GuiObject, BackgroundTransparency 1, attributes CandyFace = "<face name>",
             CandyRadius, CandyStyle = "brick" | "tile"
  Studs      Frame holder, full size, ZIndex z − 1 (BZ.Studs 1: BEHIND the side band), attributes
             StudArea (Vector2 x0, x1), StudScale
    StudN    front-view stud: AnchorPoint (0.5, StudShow) at the top edge, x spread over StudArea,
             SizeConstraint RelativeYY, Size StudW × StudH × StudScale of the brick's height,
             UICorner 0.3, UIStroke Ink (StudStroke), UIGradient "Fill" (Rotation 0: light → body →
             shade), attribute CandyStud = "front"
  Lip        the side band: Frame, full size, ZIndex z (BZ.Lip 2), Palette.X.Lip, UICorner,
             UIStroke Ink 4 px (BaseThickness = 4) — the outline of the whole brick
  <Face>     Frame "Face" (BaseBadge: "Swatch"), top 84 % (tile 88 %), ZIndex z+1,
             white + UIGradient "Fill" {0: Top + CapLight, CapStop/2: same, CapStop: Top, 1: Bottom}
             (Rotation 90), UICorner
    Spec     the glint: a white rounded dash at the top left (SpecAlpha transparency)
    Shine    full-size white overlay, Visible = false until UiFx.shine sweeps it; UIGradient
             "Band" (Rotation 20, Offset (-1, 0) = hidden)
    Stud     (round plate only) the raised centre stud: attribute CandyStud = "raised", Ink outline,
             a lit "Cap" (UIGradient "Fill")
  …content   Icon / Caption / Label at ZIndex z+2 (Theme.BZ.Content 4); overlays at BZ.Overlay (6),
             text over overlays at BZ.Top (7)
```

Studs seen from above (`Theme.topStud` / `studRow`): the Frame itself is the shadow disc (attribute
CandyStud = "top"), its child "Cap" the lit disc (UIGradient "Fill", 45°), no outline — 2 Frames +
2 UICorners + 1 gradient each. `UiFx.setCandy` recolours a brick's cap gradient, side band and
every stud (the Studs holder's children and any child of the root or the face with a CandyStud
attribute); `UiFx.setStuds(root, n, look?, {area?, scale?})` builds front studs at runtime with the
same geometry, `UiFx.paintStuds(root, colors)` gives each its own colour (Mythic).

A **candy** (v1/v2, the fishing widgets until UI v4 rebuilds them) is the same contract without
studs, glint or cap:

```
<Root>       any GuiObject, BackgroundTransparency 1, attributes CandyFace = "<face name>", CandyRadius
  Lip        Frame, full size, ZIndex z, Palette.X.Lip, UICorner, UIStroke Ink 3 px (BaseThickness = 3;
             a candy keeps 3 until v4 rebuilds it — its layout gaps were tuned with it)
  <Face>     Frame "Face", top 92 % (LIP = 0.08), ZIndex z+1,
             white + UIGradient "Fill" Top → Bottom (Rotation 90), UICorner
    Gloss    white band in the top 44 %, UIGradient "Fade" 0.42 → 1 (Night: thin 0.94 × 0.3, faint)
    Shine    as on a brick
  …content   Icon / Caption / Label at ZIndex z+2 (Theme.Z.Content 3); overlays at Z.Overlay (5)
```

Runtime colours (built with `color`, `UiFx.setCandy(root, Color3)`) become the swatch
`UIConfig.swatchFor(colour)`; the base badge uses `BaseSwatches`. Children render above their parent (ZIndexBehavior
Sibling), so anything that must appear *behind* a brick (glow, rays) is a child with ZIndex 0.
Outlines are drawn for a 720 px tall screen: every UIStroke made by Theme/UiFx carries a
`BaseThickness` attribute and `UiFx.fitStrokes(hud)` (HudController) scales them to the real screen
height (×0.65 … ×1.5; text outlines at least 2.5 px), including widgets cloned later. Text tiers are
fitted the same way by `UiFx.fitText(hud)` (§1 "Type scale"). Note: Lune stores `UICorner.CornerRadius` as
the four per-corner radii, so in RbxSim read `TopLeftRadius` (or `CandyRadius`), not `CornerRadius`.

### 6.3 Theme (builder, `tools/builder/gui/Theme.luau`)

| function | what |
|---|---|
| `Theme.UI`, `Theme.P`, `Theme.TYPE`, `Theme.INK`, `Theme.WHITE` | UIConfig, its palette, the type scale, Ink, white |
| `Theme.Z` | ZIndex layers inside a candy: `Behind 0, Lip 1, Face 2, Content 3, Overlay 5, Top 6` |
| `Theme.BZ` | … inside a brick: `Behind 0, Studs 1, Lip 2, Face 3, Content 4, Overlay 6, Top 7` |
| `Theme.LIP`, `Theme.STROKE`, `Theme.CANDY_STROKE`, `Theme.FONT`, `Theme.MIN_TEXT`, `Theme.HOTBAR` | 0.08 (candy), 4 px (bricks, sockets), 3 px (legacy candies), Nunito Heavy, 12 px, 74 px |
| `Theme.BRICK`, `Theme.TIER_OUTLINE` | `UIConfig.Brick`; text outline per tier `{Title 4.5, Button 4, Body 3.5, Small 3}` |
| `Theme.brick(root, token, opts?)` → face | makes `root` a brick (§6.2); opts: `studs` (count), `studArea` ({x0, x1}), `studScale` (1; a tall 2x2 brick ~0.55), `tile`, `lip`, `radius`, `stroke` (4), `color`, `faceName`, `spec` (false or {x, y, w, h}), `shine` (false to omit), `z` (BZ.Lip) |
| `Theme.tile(root, token, opts?)` → face | a smooth tile: `brick` with `tile = true` (no studs, TileLip, TileRadius) |
| `Theme.topStud(parent, name, props?)` → Frame | a round stud from above (plates, pips); props: Frame props + `Token` / `Color` |
| `Theme.studRow(parent, {Area = {x0, y0, x1, y1}, Count, Rows?, Size?, Token? / Color?, ZIndex?, Name?})` → holder | rows of top studs over a plate (the minigame baseplate, the card's gaps — UI v4) |
| `Theme.roundPlate(button, token, opts?)` → face | a round brick with a raised centre "Stud" (opts `stud` = diameter share 0.66, `lip` 0.1) — the v4 action button |
| `Theme.capSequence(look)`, `Theme.studSequence(look)`, `Theme.lighten`, `Theme.darken` | the brick gradients (UiFx builds the same) |
| `Theme.gradient(parent, top, bottom, rotation?, name?)` | UIGradient "Fill" (vertical by default) |
| `Theme.multiGradient(parent, colors, rotation?, name?)`, `Theme.sequence(colors)`, `Theme.numbers({{t, v}…})` | multi-stop gradients, sequences |
| `Theme.candy(root, token, opts?)` → face | makes `root` a (legacy) candy; opts: `radius` (0.5), `lip`, `stroke` (3 = `Theme.CANDY_STROKE`; 0 = none), `color` (runtime colour → `swatchFor`), `transparency`, `faceName`, `gloss` / `shine` (false to omit), `z` |
| `Theme.candyButton(parent, name, token, props)` → TextButton | candy or brick button with `Icon` / `Caption` children; props: any TextButton props + `Icon`, `Caption`, `Layout` ("stack": icon over caption, "row"), `Radius` (0.3), `Square`, `Tier`, `MaxTextSize`, `MinTextSize` (default 12), `CandyOpts`, `Brick` (true or `Theme.brick` opts: a brick button, content at BZ.Content — Home) |
| `Theme.pill(parent, name, token, props)` → Frame | candy pill (or, with `Brick`, a brick / tile — the toasts) with an overhanging emoji `Icon` (or a white `IconSocket` with `Socket = true`) and a centred `Label`; props: `Icon`, `IconScale` (1.35), `Text`, `Tier`, `MaxTextSize`, `Color`, `CandyOpts`, `LabelProps`, `Brick` |
| `Theme.panel(parent, name, props)` → Frame | Night glass panel (or `Token = "Cream"` card), radius 0.16, thin gloss |
| `Theme.socket(parent, name, emoji, props?)` → Frame | a white 1x1 round tile (white → light grey, Ink outline, inner "Rim") with an upright emoji child (`IconName`, default "Icon"); emoji "" = empty socket |
| `Theme.label(parent, name, props)` → TextLabel | white Nunito Heavy text, Ink TextStroke; extra keys `Tier` (type scale: attribute `TextTier` + constraint TYPE[tier] / −2, and at least `TIER_OUTLINE[tier]` unless `Outline = false` or `TextStrokeTransparency = 1`), `MaxTextSize`, `MinTextSize`, `Outline = px` (UIStroke "Outline" on the text), `OutlineColor`, `TextGradient = {top, bottom}` (UIGradient "TextFill") |
| `Theme.icon(parent, name, emoji, props?)` → TextLabel | emoji label, no Ink outline, Rotation 0, ZIndex Content; `Sticker = true` (or px) adds a white Contextual UIStroke "Sticker" (3 px at 720) |
| `Theme.gloss(face, radius, props?)`, `Theme.spec(face, opts?)`, `Theme.shine(face, radius)` | the face layers on their own |
| `Theme.rarityGradient(parent, rarityId, rotation?)` | rarity gradient; Mythic gets rainbow stops + attribute `Rainbow = true` (animate with `UiFx.rainbow`) |
| `Theme.corner`, `Theme.stroke(parent, px, transparency?, color?)` | small helpers; `stroke` is Ink + BaseThickness (the legacy flat-colour table `Theme.C` is gone: colours come from UIConfig) |

### 6.4 UiFx (client, `require(ReplicatedStorage.Shared.UiFx)`)

"timers" = TweenService + `task.delay` only (no connection); "frame" = the shared scheduler (one
RenderStepped connection for all running frame effects, disconnected when none runs).

| function | kind | notes |
|---|---|---|
| `press(button, {scale?, sound?})` → unbind | 3 conns | squash 0.88 on press, Back-Out spring on release (also when the finger leaves the button) |
| `popIn(gui, {from?, time?, delay?, rotate?})` | timers | UIScale from → 1, Back Out (0.3 s), optional −6° → 0 |
| `popOut(gui, {time?, to?, destroy?, hide?})` | timers | Back In to `to`, then destroy / hide |
| `bump(gui, peak?, time?)` | timers | 1.22 → 1 spring (counters, rewards) |
| `slam(gui, from?, time?)` / `stamp(gui, rotate?, time?)` | timers | 2.2 → 1 + small shake / 3 → 1 with a −16° turn |
| `pulse(gui, peak?, period?)` → stop | timers | 1 ↔ 1.08, Sine, 0.8 s |
| `wiggle(gui, angle?, swings?, time?)` | timers | ±6°, 3 swings, 0.4 s; restarts cleanly, returns to the rest rotation |
| `shake(gui, amount?, time?)` | timers | Position jitter ±1.5 %; **no effect inside a UIListLayout** (use wiggle there) |
| `shine(gui, time?)` | timers | sweeps the candy's `Shine.Band`; non-candies get a temporary overlay with the same UICorner |
| `shineLoop(gui, {interval?, time?, delay?, when?})` → stop | timers | idle shine every 3.5 s while visible (and `when()`) |
| `glowRing(gui, {color?, time?, scale?, thickness?, filled?, loop?, interval?, z?})` → stop | timers | expanding ring (or a filled copy behind a candy) 1 → 1.5, fading; stop also fades this call's live rings in 0.1 s |
| `ripple(gui, color?)` | timers | small one-shot ring for taps |
| `rays(gui, {colors?, count?, speed?, size?, maxPx?, width?, transparency?, glow?, halo?, breathe?, grow?, z?})` → `Rays` | timers | sunburst behind `gui` (ZIndex 0): core rays (+ halo quads and breathing 1↔1.06 by default on PC, off on touch), glow discs; grows 0→1 in `grow` (0.4 s, Quad Out); `speed` °/s with a sign (negative = counter-rotate); `maxPx` caps the diameter; `hole` (0…0.9, share of the radius) leaves the middle empty (no glow discs then) and `growFrom` (0) starts the growth at that size. The handle: `rays()` or `rays.stop()` removes, `rays:Destroy()` for Trove, `rays:settle({alphaAdd = 0.25, spinMul = 0.5, time = 0.6})` calms it after the reveal (also stops breathing), `rays.holder` = the FxRays frame |
| `confetti(container, {count?, colors?, origin?, spread?, power?, duration?, z?})` → stop | frame | squares/strips, gravity, flutter, fade in the last 30 %; ≤ 40 alive on touch devices, ≤ 60 otherwise (all bursts together; `confettiCap()`, `liveConfetti()`) |
| `confettiPop(container, {same options})` → stop | timers | the same pieces on tweens only (arc up Quad Out, down Quad In, spin, fade): no frame job — for moments when the rest is idle (joining, the base banner) and cheap bursts; shares the confetti cap |
| `burst(container, {count?, colors?, origin?, power?, time?, z?, size?})` → stop | frame | round sparks flying out of `origin` (hit in the zone, reward); `size` multiplies the spark size |
| `sparkles(gui, {icons?, rate?, size?, area?, duration?, z?})` → stop | timers | ✨/⭐ popping around the edges |
| `floatText(container, text, {position?, size?, color?, colors?, rise?, time?, rotate?, z?, to?, travel?})` → label | timers | «ОТЛИЧНО!», «+1»: pop, rise 8 %, fade (0.8 s); with `to` it first flies out of `position` to `to` (Back Out, `travel` 0.3 s, growing on the way), then rises — «+N 💰» out of the price chip |
| `countUp(label, from, to, time?, format?)` → stop | frame | Quad Out; `format` is a function or `"%d"`; stop jumps to the final value |
| `rainbow(gradient, {speed?, colors?, spin?})` → stop | frame | hue cycle (30 Hz); stop restores the colours |
| `timerBar(fill, duration, colors?)` → stop | frame | width 1 → 0, green → yellow → red |
| `flash(layer, color?, time?, from?, hold?)` | timers | full-screen `from` (0.6) → 1 over `time` (0.25 s) after `hold` (0); at most 3 per second (extra calls are dropped) |
| `flashBig(layer, color?)` | timers | the big-moment preset: from 0.12, hold 0.05 s, fade 0.45 s (unused: not for catch landings, see `shockwave`) |
| `shockwave(layer, origin, {color?, colors?, size?, time?, thickness?, glow?, z?})` | timers | the landing hit at `origin` (shares of the layer): "FxShock" ring (`color` or a `colors` gradient) from 0.3 to `size` (1.3) layer heights over `time` (0.45 s), a thin white "FxShockInner" ring 0.06 s later, a soft "FxShockGlow" disc (`glow` = start transparency, 0.55); `thickness` 14 px at 720 (thinner on phones), ZIndex 60; everything destroyed after `time` |
| `fovPunch(deg, tIn?, tOut?, easeIn?)` → stop | frame | the ONLY writer of `Camera.FieldOfView`: base + deg (negative = zoom in) over `tIn` (0.08 s, Quad Out; `easeIn` = Sine In wind-up), back over `tOut` (0.35 s, Sine); punches add up, the sum is clamped to ±8°; the base is restored at the end (an outside change of the FOV becomes the new base). Never set FieldOfView yourself while punches may run |
| `edgeVignette(layer, color \| {colors}, alpha, period?, opts?)` → stop(fade?) | timers | 4 edge bands ("FxVignette", ZIndex 90): transparency `alpha` at the edge → clear inside; `colors` run edge → inward. `period` = full pulse cycle between alpha and `opts.pulseTo` (alpha + 0.2), clamped to ≥ 0.34 s. opts: `fadeIn` (0.35 s), `from` (start transparency, 1), `build` (the fade-in eases in — Quad In — so it builds up to its end), `cycle` ({colors}: each side its own colour, running round the frame; one frame job while it lives), `pulseTo`, `hold` (auto-stop after N s), `fadeOut` (0.25 s), `size` (band, 0.24 of the screen height), `z`; `stop(0)` cuts it at once. E.g. Epic+ tension `edgeVignette(hud, {Bottom, Top}, 0.5, nil, {from = 0.85, fadeIn = LeapTime − 0.3, build = true, size = 0.13})` cut with `stop(0)` on the landing, bite `edgeVignette(hud, {Sun.Top, Sun.Bottom}, 0.55, 0.45)`, perfect hit `edgeVignette(hud, Gold.Top, 0.8, nil, {fadeIn = 0, hold = 0})` |
| `flyTo(layer, from, to, {text?, color?, time?, size?, arc?, onArrive?})` → stop | frame | an emoji (or a glyph like «★» in `color`, Ink-stroked) flies on an arc between two widgets (card → counter) |
| `trail(gui, {count?, lag?, transparency?})` → stop | frame | ghost copies following a moving widget (minigame needle) |
| `cameraShake(amplitude?, time?)` → stop | render step | gentle translation-only shake (Legendary/Mythic) |
| `fadeOut(gui, time?)` | timers | every background/text/stroke/ViewportFrame under `gui` to transparent |
| `setCandy(root, token \| swatch \| Color3)` | — | recolour a candy or a brick (states, toast kinds, base swatch; a Color3 becomes `swatchFor`); a brick's cap gradient and all its studs follow (§6.2) |
| `setStuds(root, count, look?, {area?, scale?})` | — | front studs on a brick at runtime (0 removes; ≤ `Brick.MaxStuds`); `look` defaults to the face's colours, area / scale to the holder's attributes — big broadcast toasts |
| `paintStuds(root, colors)` | — | one colour per front stud, cycling (the Mythic rainbow) |
| `fitStrokes(root)` → unbind | 2 conns | see 6.2 (text outlines ≥ 2.5 px) |
| `strokeThickness(stroke)` → px | — | the stroke's rest thickness on this screen (what fitStrokes sets from `BaseThickness`): restore to it, never to a live value another tween may have changed |
| `fitText(root)` → unbind | 2 conns | the type scale for every `TextTier` label, also ones added later (§1); HudController runs it on the HUD |
| `textSize(tier)` → px | — | the tier's size on this screen (what fitText sets) — for width maths |
| `sound(name, volume?, pitch?)` | — | "click", "tick", "pop"/"ping", "swoosh", "splash" (pitch 0.5 = heartbeat), "swim" or an rbxasset id; 4 pooled copies per sound (round robin), `pitch` = PlaybackSpeed |
| `arpeggio(rarityId, volume?)` → stop | timers | rising major arpeggio of "ping" (1, 1.26, 1.5, 2 …), 0.07 s apart: Common 1 note, Rare 2, Epic 3, Legendary 4, Mythic 7 (+ an octave up); stop cancels the notes not yet played |
| `scaleOf(gui)`, `faceOf(root)`, `tween(…)`, `stagger(items, gap?, fn)`, `sequence(colors)`, `sampleColors(colors, k)`, `lighten`, `darken`, `schedule(step, cleanup?)` → stop, `activeJobs()` | — | helpers; `scaleOf` returns the shared UIScale "FxScale" (FishingController uses the same one) |

### 6.5 HUD contracts (v2)

- **Catch counter** (`HUD.Status.CatchCounter`): HudController owns its `Label.Text` (the number
  only, «12» — the 🐟 `Icon` says what it counts) and
  `Visible` from the Player attribute `FishCaught`. While the HUD ScreenGui has a number attribute
  `CounterHold`, the counter shows that number and plays nothing; set it (e.g. to `Total − 1`
  from the Caught data) synchronously when the catch starts (FishingController: on "Caught",
  before the leap and the card) — HudController reacts to
  `FishCaught` one frame later, so the same frame is enough. Clear it (`nil`) when the flying 🐟
  arrives: the counter shows `FishCaught` and plays the arrival (bump 1.3, 🐟 wiggle, «+N»,
  tick at pitch 1.3). `flyTo(hud, from, counter, {onArrive = …})` stays the way to fly the fish.
  While the 🐟 is on its way, set the string attribute `CounterIncoming` = its rarity id: a
  counter that is not shown yet (held at 0 — the first catch) pops in with «🐟 0», so the fish
  has a target, and the arrival plays in the rarity colours (bump 1.45, a glow ring, «+N» at the
  Button tier in the rarity gradient). Clear it together with `CounterHold` (HudController keeps
  the rarity until the arrival).
- **Toasts**: `NotifyController.Show(text, kind?, look?)` from any client module; kinds as in
  `UIConfig.ToastKinds` (`"Legendary"` / `"Mythic"` for server-wide rare-catch broadcasts; the
  server sends them as the Notify kind, one string «Who: what» that the client splits at the
  first ": " into two lines); `look = { swatch?, icon? }` overrides the colour/icon.
  No toast while the catch is on screen (the HUD has `CounterHold`, or `HUD.Fishing.CatchCard` is
  Visible); while `Minigame` or `BiteAlert` is Visible one toast shows — on phones none but
  danger (the rest queue); while a ghost (`FxMinigameWin` / `FxMinigameMiss`) plays or a hit word
  (`Minigame.FxFloat`) rises, none but danger on every screen; keep those names and drive them
  through `Visible`.
- **Off-screen trophy chip**: `FishingFxController.OtherTrophy` (Signal: `player, basePosition,
  rarity`) fires on every client but the catcher's when a Legendary / Mythic pillar goes up;
  NotifyController clones `HUD.TrophyPointer` (children `Body` — a candy with `Icon` —, `Tip`,
  `BaseRing.Stroke`) as «TrophyChip» for `FishingConfig.Fx.PillarTimeOther[rarity]` s. Stage 3
  can reuse the signal (e.g. a theft alarm pointer) and the template.
- **Base banner** (`HUD.BaseBanner`): HudController only; never shown by other modules.
- **Catch card time**: `UIConfig.CatchCardTime[rarity]` (seconds of auto-close).

### 6.6 Rules for the next agents

- Build new widgets as bricks with Theme (brick / tile / topStud / studRow / roundPlate /
  candyButton or pill with `Brick` / label / icon / socket) and animate with UiFx — no hand-rolled
  colours or tweens; new colours go into UIConfig, the brick's proportions into `UIConfig.Brick`.
  Brick content goes at `Theme.BZ.Content` (the studs need the layer behind the side band); keep
  the candy names (Lip / Face / Fill / Shine) so `setCandy` and the tests keep working.
- CAPS for badges, buttons, banners, chips and titles through `TextUtil.upper` (Cyrillic);
  sentence case for hints and plain toasts. Icons upright; stickers in a white socket or with
  `Sticker = true`. No pills in new widgets.
- Give every label a text tier (`Tier = …`) and a box at least that tall; no `MinTextSize` below 12.
- Effects that run right after joining (the base banner, the badge) are timer-only (`confettiPop`,
  no sparkles left behind after ~2.5 s): client tests take their idle baselines soon after a
  player joins.
- The camera's FieldOfView belongs to `UiFx.fovPunch`; screen edges to `edgeVignette`; on touch
  devices rays come without halo quads and capped (`maxPx`) — mind the fill rate on phones.
- Bind `UiFx.press` once per button at Start (its connections live as long as the HUD).
- **Idle and ambient effects must be timer-based** (shineLoop, pulse, glowRing loop, rays,
  sparkles): client tests compare connection counts at two moments (stage2_client "unequip and
  respawn…", "leaks…", hud_style "idle HUD"). Frame effects (confetti, burst, countUp, rainbow,
  timerBar, flyTo, trail) are for events and must be stopped — keep their stop function in the
  widget's Trove; a rainbow left running on a hidden card is a leak.
- Inside a UIListLayout, Position is ignored and a UIScale re-flows the siblings (the scale origin
  is the AnchorPoint): prefer wiggle / bump there, never shake.
- Keep names: animate by adding children (FxScale, FxRing, FxRays, FxFloat… are created and removed
  by UiFx), never by renaming or re-parenting contract widgets.
- Recipes. Catch card (FishingController): `rays(raysHolder, {colors = UIConfig.Rarity[r].Rays,
  maxPx = …})` in a transparent holder behind the card and `rays:settle()` after the last beat,
  `popIn(card, {rotate = -6})`, `confetti(hud, {count = …, origin = the held fish on screen})`,
  a count-up with `FishingRules.FormatCoins`, `stamp(mutationBadge)`, Legendary/Mythic:
  `shockwave(hud, origin)` + `cameraShake()` + `fovPunch()` at the landing (never a full-screen
  flash); on close `flyTo(hud, start, counter, {onArrive = clear CounterHold and CounterIncoming})`
  from a fixed start point (an invisible `FxFlyFrom` frame placed once — `flyTo` reads `from`
  when each icon starts, so never a widget that is destroyed meanwhile). Mind the phone fill: the
  card's big candy draws its lip as a band (no full-size lip quad), the dim is bands around the
  card. Action button:
  `Theme.candyButton(…, "Sky", {Radius = 0.5, Square = true})`, `setCandy` per state,
  `glowRing(button, {loop = true})` while it matters, `shineLoop` when idle, `ripple` on tap.
