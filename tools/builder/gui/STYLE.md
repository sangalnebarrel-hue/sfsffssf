# UI & FX style guide — "Candy Splash" (UI v1, foundation v2)

The user's brief: «мега красивый интерфейс и мега красивые пёстрые анимации, чтобы все были в шоке».
The world stays calm (art direction v4, tools/builder/DESIGN.md §1); the **interface and the effects
are where the colour explodes** — like the top Roblox simulators (Pet Simulator 99, Grow a Garden,
Fisch, Steal a Brainrot): chunky, glossy, juicy, bouncy, rainbow on the rare stuff.

Everything here is built from plain GUI instances (Frame, TextLabel/TextButton, UICorner, UIStroke,
UIGradient, UIScale, ViewportFrame) and built-in particle/sound content — **no uploaded images or
asset ids** (we cannot upload). Emoji are our icons (they render in colour in Roblox).

## 1. Look

**Shapes.** Big rounded shapes (UICorner 0.25–0.5 of the short side; pills for bars), thick dark
outline (UIStroke 3 px at 720p, colour `Ink` #141A2E, ApplyStrokeMode Border), and a **lip**: a darker
copy of the shape 6–8 % of its height lower, behind it (Frame named `Lip`), so every button looks
like a 3D candy. Inner highlight: a white UIGradient band in the top 35 % (Frame `Gloss`,
transparency 0.65→1) — the "wet" look.

**Gradients.** Every coloured surface has a vertical UIGradient: light on top → saturated at the
bottom (Rotation 90). Base colours (top → bottom):

| token | use | top | bottom |
|---|---|---|---|
| `Sky` | cast / primary action | #5FD8FF | #1F7BF0 |
| `Sun` | bite / alert | #FFD23F | #FF6A1F |
| `Leaf` | reel / success / home | #8BF26A | #1FB04F |
| `Berry` | stop / danger / miss | #FF7A8A | #E0304A |
| `Grape` | special / epic | #D69BFF | #7A35F0 |
| `Gold` | money / legendary | #FFF07A | #FFA51F |
| `Night` | panels, tracks | #2E3A66 | #161C38 (BackgroundTransparency 0.1) |
| `Cream` | cards | #FFFDF5 | #F2EADB |
| `Slate` | disabled / waiting, no base | #C3CDE0 | #7C89A6 |
| `Mint` | Home (never confused with the Leaf «ЛОВИ!») | #8CF5E0 | #14B8A6 |
| `Water` | waiting for a bite | #5FD8FF | #1FA5C8 |

Base colours are clean swatches too (`UIConfig.BaseSwatches`, by the BaseConfig colour Id):
Red = Berry, Purple = Grape, Cyan = Sky, Orange = Sun, Green #6FF0B0→#14A86A, Pink
#FF9AD5→#E0489A, Blue #7AA8FF→#2F62E0, Yellow #FFE65C→#F0B400; any other colour goes through
`UIConfig.swatchFor(color)` (lighter top, saturated bottom, dark lip) — never a grey-tinted face.

Rarity themes (banners, rays, glows, confetti mixes): Common `#E3E9F0→#9AA8B8`, Rare `#6CD3FF→#2468F0`,
Epic `#E08CFF→#7B2FE8`, Legendary `#FFF27A→#FF8A1F`, Mythic = an **animated rainbow** (UIGradient with
6+ hue keypoints whose Offset/Rotation moves). Mutation badges: Gold (gold gradient + sparkles),
Neon (#4DFFF0→#19C2FF, glowing pulse), Rainbow (animated rainbow).

**Text.** Font: Nunito ExtraBold (`Font.new("rbxasset://fonts/families/Nunito.json", ExtraBold)`;
Heavy where the family has it). White text with a dark outline (TextStrokeTransparency 0, colour
`Ink`, plus a UIStroke on the label for thickness 2–3 px on big titles). Big titles may have a
UIGradient on the text (white → pale gold). Never below 12 px on a phone (UITextSizeConstraint).
Short words, upper case for buttons and titles («ЗАБРОСИТЬ», «КЛЮЁТ!»).

**Type scale.** Text that means the same thing has the same size on one screen. Four tiers
(`UIConfig.Type`, Roblox TextSize = line height in px on a 390 px tall screen):

| tier | px | used for |
|---|---|---|
| `Title` | 22 | base badge, minigame title, rarity banner, fish name |
| `Button` | 18 | action caption, «СМОТАТЬ», «ДОМОЙ», Legendary/Mythic broadcasts |
| `Body` | 16 | hints, Help, toasts, the catch counter |
| `Small` | 14 | chips (weight, price), «Тапни, чтобы закрыть» |

A label gets its tier with `Theme.label(…, { Tier = "Body" })` (attribute `TextTier`);
`UiFx.fitText(hud)` (HudController) sets Max = tier × clamp(H / 390, 1, 1.6), Min = Max − 2 for
every tiered label, also ones cloned later. Give the box at least that height; long copy is
shortened (or the widget grows a line), never shrunk below its tier. Display text (the giant
rarity title, the base banner name, cooldown digits) is box-driven, not tiered. Text outlines
are at least 2 px on any screen (`UIConfig.Fx.TextStrokeMin`).

**Icons.** Emoji in their own TextLabel (TextStrokeTransparency 1), slightly rotated (−8°) for life:
🎣 🐟 🏠 💰 ⭐ ✨ ❗ 💪 🔥 🌈 👑.

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

- **HUD chrome** (tools/builder/gui/Hud.luau, HudController, NotifyController): base badge (glossy pill
  in the base swatch, flag in a socket, Title text; shines only when the base arrives); the base
  banner (first assignment: «ТВОЯ БАЗА» / «ЛАЗУРНАЯ!» across the centre in the base swatch, waving
  🚩, rays, confetti, a fanfare; after 2 s it shrinks into the badge, which bumps); catch counter
  (gold pill, 🐟 in a white socket, bump + «+N» + a higher tick when the fish arrives — held while
  the HUD has `CounterHold`); Home button (Mint candy, dark caption ribbon like the action button,
  🏠 wiggle on press; cooldown: draining veil, digits on the face, «ЖДИ» over the veil, the house
  fades; one shine when ready); toasts (candy pills by kind with an icon in a socket, slide-down +
  bounce, shine; a column right under the status stack — 3 on a PC (clear of the chat window), 2
  on a tablet, 1 on a phone (above the avatar's head); none while the catch is on screen, 1 over
  the bite / minigame (on phones none but danger), the rest queue — a toast pushed off in the
  first half of its life comes back; Legendary (gold, 🌟) and Mythic (rainbow, 🌈) broadcasts
  in two lines — who (Small) over what (up to Title, the rarity word in capitals, light-gold /
  running-rainbow letters), Mythic adds one thin rainbow edge pulse; leaving: rise + fade, ≥ 0.7 s apart).
  Only the primary CTA idles (shine + breathing); the chrome stays calm.
- **Fishing UI** (tools/builder/gui/Fishing.luau, FishingController): the action button is the star —
  a big round candy button (ActionArea, 0.66 of the HUD height, max 320 x 240) whose gradient, icon and
  caption ribbon change by state (ЗАБРОСИТЬ 🎣 → ЖДЁМ… with a bobbing float and 1–2 nibbles «?» →
  ПОДСЕЧЬ! «!» → ЛОВИ! 🎯; Slate ⏳ while waiting on the server, К ПИРСУ 🧭 far from the spot — it
  shows the way, never scolds: a calm 💡 hint, the compass turns, the guide beam flares; ВЗЯТЬ
  in gold at the spot), glow rings while it matters, shine on idle, press squash, ripple on tap; a key
  chip («F» / «R2») on its shoulder without touch. «СМОТАТЬ» (≥ 44 px, ≥ 22 px above the circle)
  only while waiting: it pops out once a fish bites. Bite alert: «КЛЮЁТ!» slams in with a sun flash and a
  FOV punch, sun edge glow, one BITE_BEAT for the plate, the button and the swinging «!» glyphs, a
  gradient countdown bar (green→yellow→red); on touch the plate is a tap pad, a 👆 helps the first
  two bites, and the plate gets a little lower (or moves aside) when it would hide the own diving
  bobber. Minigame: candy track, glossy green zone with a rider by rarity (🐟 🐠 🐡 🦈 🐉; Legendary+
  bigger and glowing) and a glow pulse, needle ▼ with two fading ghost copies (under the zone), a
  light Rare rim, Epic+ outline/aura in the rarity colours, Legendary/Mythic slam the giant rarity
  word over the panel once; on phones the panel stands beside the own bobber when it would cover
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
  sweeping rainbow — with a glow ring) left of the character, never over the leap; the status badge
  and the counter fade out, the button freezes, Epic+ get an edge vignette, Legendary/Mythic an
  accelerating heartbeat and a slight FOV wind-up while the fish leaps. On the landing
  (`FishingFxController.OwnFishLanded`) **no full-screen flash**: a shockwave (`UiFx.shockwave`) and
  sparks from the fish's point, for Epic+ a short edge glow in the rarity colours (≤ 0.4 s), shake and
  FOV punch, confetti; for Epic+ the rarity rays start around the fish (empty middle) with the giant
  rarity title (TitleSlam; Legendary/Mythic letter by letter) — a title stage of 0.5 / 0.8 / 0.9 s
  (Epic / Legendary / Mythic) — then the card is born at the fish and settles (the rays follow it): a
  landscape trophy card on phones (fish left, name and chips right), the 380 x 384 square elsewhere,
  a dim around it (letterbox bars on phones; none for Common). Its beats: rarity (the title flies
  into the banner at once) → name → «НОВИНКА!» → chips → price count-up and landing → mutation
  (corner stamp, «×N», recount, the outline in its colours) → the close hint; then everything calms
  down. A tap skips to the end, a tap at least 0.6 s later closes; the card shrinks towards the
  counter, a 🐟 with ✨ flies in (the counter holds its number meanwhile) and the trophy over the
  head flashes once more (`FishingFxController.ReplayOwnTrophy`) and stays ≈ 3 s.
  Rarity tiers (dim, rays, confetti volleys, burst, hold, auto-close): `REVEAL` in FishingController.
- **World FX** (FishingFxController, + FishingService for the broadcast): cast with a sparkly trail on
  the bobber and a whoosh, a splash + expanding ripple rings on landing, slow ripples and nibbles
  (the own bobber — 2.2× the template — dips half a stud with a ring, drops and a «?») while
  waiting, the bite: a plunge, a big splash, rings, a bouncing «!» badge with
  stars and a blinking outline on your own bobber; a wake while reeling. On a catch a spout, then the
  fish **leaps out of the water** and flies in an arc (spinning, rarity-coloured sparkle trail) to
  above the fisher's head — `OwnFishLanded` fires the frame it lands — then a halo, a nameplate
  (rarity, name, mutation, price; sized in studs + pixels; above the fish for others, beside it —
  to the right — for your own, where the title and the card are) and the rarity aura around the
  held fish for `FishingRules.HoldFishTime(rarity)` s (≈ 3 s longer than the catch card, so your own
  trophy is still there when the card closes; then `ReplayOwnTrophy` pops it once more: ball, halo,
  sparks, nameplate bump, a chime, a short pillar for Legendary/Mythic); Legendary/Mythic: a light
  pillar (narrower on your own screen; for everyone else wider with distance — ≥ 25 px from the
  neighbouring pier — and longer, `Fx.PillarTimeOther`; their broadcast toast lands with it) and a
  confetti burst, seen by everyone. A lost fish: the line flashes, the bobber pops up, a splash and
  a tail flick away.

## 4. Budgets (phones first)

- At most ~60 temporary GUI objects alive at once from effects (confetti 40 max on phones, 60 on PC);
  everything destroyed when done. No RenderStepped/Heartbeat connection while nothing animates.
- World: at most 2 ParticleEmitters active per player at a time; parts for ripples/pillars are
  client-side, CanCollide/CanQuery/CanTouch false, CastShadow false, destroyed after use.
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

## 6. API (UI v1 foundation + v2 additions)

Where things live:

| what | file | side |
|---|---|---|
| colours: palette tokens, rarity/mutation styles, toast kinds, confetti mixes, FX limits | `src/ReplicatedStorage/Shared/Config/UIConfig.luau` (pure: Color3 only) | both |
| builder helpers (candies, labels, icons, gradients) | `tools/builder/gui/Theme.luau` (reads UIConfig via `U.loadPure`) | Lune |
| motion library | `src/ReplicatedStorage/Shared/UiFx.luau` | client |
| reference implementation | `gui/Hud.luau` + `HudController` + `NotifyController` | both |
| tests | `tests/uifx.test.luau`, `tests/hud_style.test.luau` | sim |

### 6.1 UIConfig (one source of colours)

`Ink`, `White`; `Palette.<Sky|Sun|Leaf|Berry|Grape|Gold|Night|Cream|Slate|Mint|Water>` =
`{ Top, Bottom, Lip }` (Slate = disabled / waiting; Lip = the dark bottom band of a candy);
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
FlashMinInterval = 0.34, StrokeHeight = 720, TextStrokeMin = 2, FovPunchMax = 8, SoundPool = 4 }`.
FishConfig's rarity/mutation `Color`s stay the flat colours the stage-2 tests check; use
`UIConfig.Rarity` / `Mutations` for gradients and FX.

### 6.2 The candy (structure contract shared by Theme and UiFx)

```
<Root>       any GuiObject, BackgroundTransparency 1, attributes CandyFace = "<face name>", CandyRadius
  Lip        Frame, full size, ZIndex z, Palette.X.Lip, UICorner, UIStroke Ink 3 px (BaseThickness = 3)
  <Face>     Frame "Face" (BaseBadge: "Swatch"), top 92 % (LIP = 0.08), ZIndex z+1,
             white + UIGradient "Fill" Top → Bottom (Rotation 90), UICorner
    Gloss    white band in the top 44 %, UIGradient "Fade" 0.42 → 1 (Night: thin 0.94 × 0.3, faint)
    Shine    full-size white overlay, Visible = false until UiFx.shine sweeps it; UIGradient
             "Band" (Rotation 20, Offset (-1, 0) = hidden)
  …content   Icon / Caption / Label at ZIndex z+2 (Theme.Z.Content); overlays at Z.Overlay (5)
```

Runtime colours (a candy built with `color`, `UiFx.setCandy(root, Color3)`) become the swatch
`UIConfig.swatchFor(colour)`; the base badge uses `BaseSwatches`. Children render above their parent (ZIndexBehavior
Sibling), so anything that must appear *behind* a candy (glow, rays) is a child with ZIndex 0.
Outlines are drawn for a 720 px tall screen: every UIStroke made by Theme/UiFx carries a
`BaseThickness` attribute and `UiFx.fitStrokes(hud)` (HudController) scales them to the real screen
height (×0.65 … ×1.5; text outlines at least 2 px), including widgets cloned later. Text tiers are
fitted the same way by `UiFx.fitText(hud)` (§1 "Type scale"). Note: Lune stores `UICorner.CornerRadius` as
the four per-corner radii, so in RbxSim read `TopLeftRadius` (or `CandyRadius`), not `CornerRadius`.

### 6.3 Theme (builder, `tools/builder/gui/Theme.luau`)

| function | what |
|---|---|
| `Theme.UI`, `Theme.P`, `Theme.TYPE`, `Theme.INK`, `Theme.WHITE` | UIConfig, its palette, the type scale, Ink, white |
| `Theme.Z` | ZIndex layers inside a candy: `Behind 0, Lip 1, Face 2, Content 3, Overlay 5, Top 6` |
| `Theme.LIP`, `Theme.STROKE`, `Theme.FONT`, `Theme.MIN_TEXT`, `Theme.HOTBAR` | 0.08, 3 px, Nunito ExtraBold, 12 px, 74 px |
| `Theme.gradient(parent, top, bottom, rotation?, name?)` | UIGradient "Fill" (vertical by default) |
| `Theme.multiGradient(parent, colors, rotation?, name?)`, `Theme.sequence(colors)`, `Theme.numbers({{t, v}…})` | multi-stop gradients, sequences |
| `Theme.candy(root, token, opts?)` → face | makes `root` a candy; opts: `radius` (0.5), `lip`, `stroke` (3; 0 = none), `color` (runtime colour → `swatchFor`), `transparency`, `faceName`, `gloss` / `shine` (false to omit), `z` |
| `Theme.candyButton(parent, name, token, props)` → TextButton | candy button with `Icon` / `Caption` children; props: any TextButton props + `Icon`, `Caption`, `Layout` ("stack": icon over caption, "row"), `Radius` (0.3), `Square`, `Tier`, `MaxTextSize`, `MinTextSize` (default 12), `CandyOpts` |
| `Theme.pill(parent, name, token, props)` → Frame | candy pill with an overhanging emoji `Icon` (or a white `IconSocket` with `Socket = true`) and a centred `Label`; props: `Icon`, `IconScale` (1.35), `Text`, `Tier`, `MaxTextSize`, `Color`, `CandyOpts`, `LabelProps` |
| `Theme.panel(parent, name, props)` → Frame | Night glass panel (or `Token = "Cream"` card), radius 0.16, thin gloss |
| `Theme.socket(parent, name, emoji, props?)` → Frame | white round socket with an emoji child (`IconName`, default "Icon"); emoji "" = empty socket |
| `Theme.label(parent, name, props)` → TextLabel | white Nunito text, Ink TextStroke; extra keys `Tier` (type scale: attribute `TextTier` + constraint TYPE[tier] / −2), `MaxTextSize`, `MinTextSize`, `Outline = px` (UIStroke "Outline" on the text), `OutlineColor`, `TextGradient = {top, bottom}` (UIGradient "TextFill") |
| `Theme.icon(parent, name, emoji, props?)` → TextLabel | emoji label, no outline, Rotation −8, ZIndex Content |
| `Theme.gloss(face, radius, props?)`, `Theme.shine(face, radius)` | the two face layers on their own |
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
| `floatText(container, text, {position?, size?, color?, colors?, rise?, time?, rotate?, z?})` → label | timers | «ОТЛИЧНО!», «+1»: pop, rise 8 %, fade (0.8 s) |
| `countUp(label, from, to, time?, format?)` → stop | frame | Quad Out; `format` is a function or `"%d"`; stop jumps to the final value |
| `rainbow(gradient, {speed?, colors?, spin?})` → stop | frame | hue cycle (30 Hz); stop restores the colours |
| `timerBar(fill, duration, colors?)` → stop | frame | width 1 → 0, green → yellow → red |
| `flash(layer, color?, time?, from?, hold?)` | timers | full-screen `from` (0.6) → 1 over `time` (0.25 s) after `hold` (0); at most 3 per second (extra calls are dropped) |
| `flashBig(layer, color?)` | timers | the big-moment preset: from 0.12, hold 0.05 s, fade 0.45 s (unused: not for catch landings, see `shockwave`) |
| `shockwave(layer, origin, {color?, colors?, size?, time?, thickness?, glow?, z?})` | timers | the landing hit at `origin` (shares of the layer): "FxShock" ring (`color` or a `colors` gradient) from 0.3 to `size` (1.3) layer heights over `time` (0.45 s), a thin white "FxShockInner" ring 0.06 s later, a soft "FxShockGlow" disc (`glow` = start transparency, 0.55); `thickness` 14 px at 720 (thinner on phones), ZIndex 60; everything destroyed after `time` |
| `fovPunch(deg, tIn?, tOut?, easeIn?)` → stop | frame | the ONLY writer of `Camera.FieldOfView`: base + deg (negative = zoom in) over `tIn` (0.08 s, Quad Out; `easeIn` = Sine In wind-up), back over `tOut` (0.35 s, Sine); punches add up, the sum is clamped to ±8°; the base is restored at the end (an outside change of the FOV becomes the new base). Never set FieldOfView yourself while punches may run |
| `edgeVignette(layer, color \| {colors}, alpha, period?, opts?)` → stop(fade?) | timers | 4 edge bands ("FxVignette", ZIndex 90): transparency `alpha` at the edge → clear inside; `colors` run edge → inward. `period` = full pulse cycle between alpha and `opts.pulseTo` (alpha + 0.2), clamped to ≥ 0.34 s. opts: `fadeIn` (0.35 s), `pulseTo`, `hold` (auto-stop after N s), `fadeOut` (0.25 s), `size` (band, 0.24 of the screen height), `z`. E.g. Epic+ tension `edgeVignette(hud, c, 0.75, nil, {fadeIn = 0.5})`, bite `edgeVignette(hud, {Sun.Top, Sun.Bottom}, 0.55, 0.45)`, perfect hit `edgeVignette(hud, Gold.Top, 0.8, nil, {fadeIn = 0, hold = 0})` |
| `flyTo(layer, from, to, {text?, time?, size?, arc?, onArrive?})` → stop | frame | an emoji flies on an arc between two widgets (card → counter) |
| `trail(gui, {count?, lag?, transparency?})` → stop | frame | ghost copies following a moving widget (minigame needle) |
| `cameraShake(amplitude?, time?)` → stop | render step | gentle translation-only shake (Legendary/Mythic) |
| `fadeOut(gui, time?)` | timers | every background/text/stroke/ViewportFrame under `gui` to transparent |
| `setCandy(root, token \| swatch \| Color3)` | — | recolour a candy (states, toast kinds, base swatch; a Color3 becomes `swatchFor`) |
| `fitStrokes(root)` → unbind | 2 conns | see 6.2 (text outlines ≥ 2 px) |
| `fitText(root)` → unbind | 2 conns | the type scale for every `TextTier` label, also ones added later (§1); HudController runs it on the HUD |
| `textSize(tier)` → px | — | the tier's size on this screen (what fitText sets) — for width maths |
| `sound(name, volume?, pitch?)` | — | "click", "tick", "pop"/"ping", "swoosh", "splash" (pitch 0.5 = heartbeat), "swim" or an rbxasset id; 4 pooled copies per sound (round robin), `pitch` = PlaybackSpeed |
| `arpeggio(rarityId, volume?)` → stop | timers | rising major arpeggio of "ping" (1, 1.26, 1.5, 2 …), 0.07 s apart: Common 1 note, Rare 2, Epic 3, Legendary 4, Mythic 7 (+ an octave up); stop cancels the notes not yet played |
| `scaleOf(gui)`, `faceOf(root)`, `tween(…)`, `stagger(items, gap?, fn)`, `sequence(colors)`, `sampleColors(colors, k)`, `lighten`, `darken`, `schedule(step, cleanup?)` → stop, `activeJobs()` | — | helpers; `scaleOf` returns the shared UIScale "FxScale" (FishingController uses the same one) |

### 6.5 HUD contracts (v2)

- **Catch counter** (`HUD.Status.CatchCounter`): HudController owns its `Label.Text` («Улов: N») and
  `Visible` from the Player attribute `FishCaught`. While the HUD ScreenGui has a number attribute
  `CounterHold`, the counter shows that number and plays nothing; set it (e.g. to `Total − 1`
  from the Caught data) synchronously when the catch starts (FishingController: on "Caught",
  before the leap and the card) — HudController reacts to
  `FishCaught` one frame later, so the same frame is enough. Clear it (`nil`) when the flying 🐟
  arrives: the counter shows `FishCaught` and plays the arrival (bump 1.3, 🐟 wiggle, «+N»,
  tick at pitch 1.3). `flyTo(hud, from, counter, {onArrive = …})` stays the way to fly the fish.
- **Toasts**: `NotifyController.Show(text, kind?, look?)` from any client module; kinds as in
  `UIConfig.ToastKinds` (`"Legendary"` / `"Mythic"` for server-wide rare-catch broadcasts; the
  server sends them as the Notify kind, one string «Who: what» that the client splits at the
  first ": " into two lines); `look = { swatch?, icon? }` overrides the colour/icon.
  No toast while the catch is on screen (the HUD has `CounterHold`, or `HUD.Fishing.CatchCard` is
  Visible); while `Minigame` or `BiteAlert` is Visible, or its ghost (`FxMinigameWin` /
  `FxMinigameMiss`) plays, one toast shows — on phones none but danger (the rest queue); keep
  those names and drive them through `Visible`.
- **Base banner** (`HUD.BaseBanner`): HudController only; never shown by other modules.
- **Catch card time**: `UIConfig.CatchCardTime[rarity]` (seconds of auto-close).

### 6.6 Rules for the next agents

- Build widgets with Theme (candy / candyButton / pill / panel / label / icon) and animate with
  UiFx — no hand-rolled colours or tweens; new colours go into UIConfig.
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
  `flash(hud)` + `cameraShake()` + `fovPunch()` at the landing; on close `flyTo(hud, card, counter,
  {onArrive = clear CounterHold})`. Mind the phone fill: the card's big candy draws its lip as a
  band (no full-size lip quad), the dim is bands around the card. Action button:
  `Theme.candyButton(…, "Sky", {Radius = 0.5, Square = true})`, `setCandy` per state,
  `glowRing(button, {loop = true})` while it matters, `shineLoop` when idle, `ripple` on tap.
