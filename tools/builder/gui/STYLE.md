# UI & FX style guide — "Candy Splash" (UI v1)

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

Rarity themes (banners, rays, glows, confetti mixes): Common `#E3E9F0→#9AA8B8`, Rare `#6CD3FF→#2468F0`,
Epic `#E08CFF→#7B2FE8`, Legendary `#FFF27A→#FF8A1F`, Mythic = an **animated rainbow** (UIGradient with
6+ hue keypoints whose Offset/Rotation moves). Mutation badges: Gold (gold gradient + sparkles),
Neon (#4DFFF0→#19C2FF, glowing pulse), Rainbow (animated rainbow).

**Text.** Font: Nunito ExtraBold (`Font.new("rbxasset://fonts/families/Nunito.json", ExtraBold)`;
Heavy where the family has it). White text with a dark outline (TextStrokeTransparency 0, colour
`Ink`, plus a UIStroke on the label for thickness 2–3 px on big titles). Big titles may have a
UIGradient on the text (white → pale gold). Never below 12 px on a phone (UITextSizeConstraint).
Short words, upper case for buttons and titles («ЗАБРОСИТЬ», «КЛЮЁТ!»).

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
| glow ring | a copy of the round shape behind it, scale 1→1.5, transparency 0.3→1 | 0.6 s, repeat while important |
| rays | sunburst of 12–16 thin wedge-ish Frames (rotated bars) in alternating rarity colours, slowly rotating (≈20°/s), behind titles and the catch card | while shown |
| confetti | 30–60 small Frames (squares/strips, random vivid colours, rotation), launched up/out then falling with gravity and spin, fading in the last 30 % | 1.6–2.2 s |
| sparkles | ✨ / ⭐ labels popping in/out at random spots around an element | while shown |
| float text | «ОТЛИЧНО!», «+1 🐟», «МИМО!» rise 8 % and fade, slight rotation | 0.8 s |
| count-up | number ticks from 0 to the value (Quad Out) | 0.6–1.0 s |
| rainbow | UIGradient colour keypoints shifted every frame (hue cycle), or Rotation spin | continuous while shown |
| flash | full-screen white/rarity-coloured Frame 0.6→1 transparency | 0.25 s |

Easing defaults: Back Out for appearing, Quad In for leaving, Sine for loops. Nothing linear except
timers. Stagger groups by 0.03–0.06 s.

## 3. Where it is used

- **HUD chrome** (tools/builder/gui/Hud.luau, HudController, NotifyController): base badge (glossy pill
  in the base colour, flag icon, shine every few seconds, bounce when the base is assigned), catch
  counter (gold pill, 🐟, bump + «+1» on each catch), Home button (Leaf candy button with lip, gloss,
  🏠 wiggle on press, cooldown as a draining overlay), toasts (candy pills by kind with an icon,
  slide-down + bounce, shine, shrink out).
- **Fishing UI** (tools/builder/gui/Fishing.luau, FishingController): the action button is the star —
  a big round candy button whose gradient/icon/caption change by state, glow rings while it matters,
  shine on idle, press squash, ripple on tap. Bite alert: slams in, «КЛЮЁТ!» shakes, ❗ wiggle, rays
  behind, a gradient countdown bar (green→yellow→red). Minigame: candy track, glossy green zone with
  a glow pulse, needle with 2–3 fading ghost copies (motion trail), on hit — burst of sparks from the
  zone, «ОТЛИЧНО!/СУПЕР!/ИДЕАЛЬНО!» float text (perfect = within 25 % of the zone centre), pip turns
  into a ⭐ with a pop; on miss — red flash, shake, «МИМО!». Catch card: the big reveal — dim backdrop,
  rays in rarity colours, card drops/pops in with a little rotation, rarity banner (Mythic: animated
  rainbow), shine sweep, confetti (more and longer for rarer fish), sparkles around the fish, price
  counts up, mutation badge stamps in, «НОВАЯ!» stamp the first time a species is caught this
  session; Legendary/Mythic add a screen flash and a gentle camera shake. A 🐟 flies from the card to
  the catch counter when the card closes.
- **World FX** (FishingFxController, + FishingService for the broadcast): cast with a sparkly trail on
  the bobber and a whoosh, a splash + expanding ripple rings on landing, slow ripples while waiting,
  a big splash, ripple burst and a bouncing «!» on the bite, spray while reeling; on a catch the fish
  **leaps out of the water** at the bobber and flies in an arc (spinning, with a rarity-coloured
  sparkle trail) to above the fisher's head (the server attaches the held fish when it lands), then a
  rarity aura (sparkles) around the held fish; Legendary/Mythic: a light pillar and a confetti burst
  at the fisher, seen by everyone. A lost fish: a splash and a tail flick away.

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

## 6. API (UI v1 foundation)

Where things live:

| what | file | side |
|---|---|---|
| colours: palette tokens, rarity/mutation styles, toast kinds, confetti mixes, FX limits | `src/ReplicatedStorage/Shared/Config/UIConfig.luau` (pure: Color3 only) | both |
| builder helpers (candies, labels, icons, gradients) | `tools/builder/gui/Theme.luau` (reads UIConfig via `U.loadPure`) | Lune |
| motion library | `src/ReplicatedStorage/Shared/UiFx.luau` | client |
| reference implementation | `gui/Hud.luau` + `HudController` + `NotifyController` | both |
| tests | `tests/uifx.test.luau`, `tests/hud_style.test.luau` | sim |

### 6.1 UIConfig (one source of colours)

`Ink`, `White`; `Palette.<Sky|Sun|Leaf|Berry|Grape|Gold|Night|Cream|Slate>` = `{ Top, Bottom, Lip }`
(Slate = disabled / waiting; Lip = the dark bottom band of a candy); `Rarity.<Common|Rare|Epic|
Legendary|Mythic>` = `{ Top, Bottom, Lip, Rainbow, Rays = {…}, Confetti = {…}, ConfettiCount, Flash }`;
`Mutations.<Gold|Neon|Rainbow>` = `{ Top, Bottom, Lip, Icon, Effect = "sparkles"|"pulse"|"rainbow" }`;
`Rainbow` (7 hues), `Confetti` (vivid mix); `ToastKinds.<info|success|warning|danger>` =
`{ Token, Icon }`; `KindColors` (flat colour per kind = palette Bottom); `NoBaseColor`;
`Tint = { Bottom, Lip }` (runtime-colour candies); `Fx = { ConfettiMaxTouch = 40, ConfettiMax = 60,
ShineInterval, FlashMinInterval, StrokeHeight = 720 }`. FishConfig's rarity/mutation `Color`s stay
the flat colours the stage-2 tests check; use `UIConfig.Rarity` / `Mutations` for gradients and FX.

### 6.2 The candy (structure contract shared by Theme and UiFx)

```
<Root>       any GuiObject, BackgroundTransparency 1, attributes CandyFace = "<face name>", CandyRadius
  Lip        Frame, full size, ZIndex z, Palette.X.Lip, UICorner, UIStroke Ink 3 px (BaseThickness = 3)
  <Face>     Frame "Face" (BaseBadge: "Swatch"), top 92 % (LIP = 0.08), ZIndex z+1,
             white + UIGradient "Fill" Top → Bottom (Rotation 90), UICorner
    Gloss    white band in the top 44 %, UIGradient "Fade" 0.42 → 1
    Shine    full-size white overlay, UIGradient "Band" (Rotation 20, Offset (-1, 0) = hidden)
  …content   Icon / Caption / Label at ZIndex z+2 (Theme.Z.Content); overlays at Z.Overlay (5)
```

Runtime-colour candies (the base badge): `Face.BackgroundColor3 = colour`, `Fill` = white → grey
(`Tint.Bottom`), `Lip = colour × Tint.Lip`. Children render above their parent (ZIndexBehavior
Sibling), so anything that must appear *behind* a candy (glow, rays) is a child with ZIndex 0.
Outlines are drawn for a 720 px tall screen: every UIStroke made by Theme/UiFx carries a
`BaseThickness` attribute and `UiFx.fitStrokes(hud)` (HudController) scales them to the real screen
height (×0.65 … ×1.5), including widgets cloned later. Note: Lune stores `UICorner.CornerRadius` as
the four per-corner radii, so in RbxSim read `TopLeftRadius` (or `CandyRadius`), not `CornerRadius`.

### 6.3 Theme (builder, `tools/builder/gui/Theme.luau`)

| function | what |
|---|---|
| `Theme.UI`, `Theme.P`, `Theme.INK`, `Theme.WHITE` | UIConfig, its palette, Ink, white |
| `Theme.Z` | ZIndex layers inside a candy: `Behind 0, Lip 1, Face 2, Content 3, Overlay 5, Top 6` |
| `Theme.LIP`, `Theme.STROKE`, `Theme.FONT`, `Theme.MIN_TEXT`, `Theme.HOTBAR` | 0.08, 3 px, Nunito ExtraBold, 12 px, 74 px |
| `Theme.gradient(parent, top, bottom, rotation?, name?)` | UIGradient "Fill" (vertical by default) |
| `Theme.multiGradient(parent, colors, rotation?, name?)`, `Theme.sequence(colors)`, `Theme.numbers({{t, v}…})` | multi-stop gradients, sequences |
| `Theme.candy(root, token, opts?)` → face | makes `root` a candy; opts: `radius` (0.5), `lip`, `stroke` (3; 0 = none), `color` (runtime colour), `transparency`, `faceName`, `gloss` / `shine` (false to omit), `z` |
| `Theme.candyButton(parent, name, token, props)` → TextButton | candy button with `Icon` / `Caption` children; props: any TextButton props + `Icon`, `Caption`, `Layout` ("stack": icon over caption, "row"), `Radius` (0.3), `Square`, `MaxTextSize`, `MinTextSize`, `CandyOpts` |
| `Theme.pill(parent, name, token, props)` → Frame | candy pill with an overhanging emoji `Icon` (or a white `IconSocket` with `Socket = true`) and a centred `Label`; props: `Icon`, `IconScale` (1.35), `Text`, `MaxTextSize`, `Color`, `CandyOpts`, `LabelProps` |
| `Theme.panel(parent, name, props)` → Frame | Night glass panel (or `Token = "Cream"` card), radius 0.16, thin gloss |
| `Theme.socket(parent, name, emoji, props)` → Frame | white round socket with an emoji child (`IconName`, default "Icon") |
| `Theme.label(parent, name, props)` → TextLabel | white Nunito text, Ink TextStroke; extra keys `MaxTextSize`, `MinTextSize`, `Outline = px` (UIStroke "Outline" on the text), `OutlineColor`, `TextGradient = {top, bottom}` (UIGradient "TextFill") |
| `Theme.icon(parent, name, emoji, props?)` → TextLabel | emoji label, no outline, Rotation −8, ZIndex Content |
| `Theme.gloss(face, radius, props?)`, `Theme.shine(face, radius)` | the two face layers on their own |
| `Theme.rarityGradient(parent, rarityId, rotation?)` | rarity gradient; Mythic gets rainbow stops + attribute `Rainbow = true` (animate with `UiFx.rainbow`) |
| `Theme.corner`, `Theme.stroke(parent, px, transparency?, color?)`, `Theme.C` | legacy helpers (gui/Fishing.luau); `stroke` is now Ink + BaseThickness |

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
| `glowRing(gui, {color?, time?, scale?, thickness?, filled?, loop?, interval?, z?})` → stop | timers | expanding ring (or a filled copy behind a candy) 1 → 1.5, fading |
| `ripple(gui, color?)` | timers | small one-shot ring for taps |
| `rays(gui, {colors?, count?, speed?, size?, width?, transparency?, glow?, z?})` → stop | timers | sunburst (core + halo rays, glow discs) behind `gui` (ZIndex 0), rotating 20°/s, breathing |
| `confetti(container, {count?, colors?, origin?, spread?, power?, duration?, z?})` → stop | frame | squares/strips, gravity, flutter, fade in the last 30 %; ≤ 40 alive on touch devices, ≤ 60 otherwise (all bursts together; `confettiCap()`, `liveConfetti()`) |
| `burst(container, {count?, colors?, origin?, power?, time?, z?})` → stop | frame | round sparks flying out of `origin` (hit in the zone, reward) |
| `sparkles(gui, {icons?, rate?, size?, area?, duration?, z?})` → stop | timers | ✨/⭐ popping around the edges |
| `floatText(container, text, {position?, size?, color?, colors?, rise?, time?, rotate?, z?})` → label | timers | «ОТЛИЧНО!», «+1»: pop, rise 8 %, fade (0.8 s) |
| `countUp(label, from, to, time?, format?)` → stop | frame | Quad Out; `format` is a function or `"%d"`; stop jumps to the final value |
| `rainbow(gradient, {speed?, colors?, spin?})` → stop | frame | hue cycle (30 Hz); stop restores the colours |
| `timerBar(fill, duration, colors?)` → stop | frame | width 1 → 0, green → yellow → red |
| `flash(layer, color?, time?)` | timers | full-screen 0.6 → 1; at most 3 per second |
| `flyTo(layer, from, to, {text?, time?, size?, arc?, onArrive?})` → stop | frame | an emoji flies on an arc between two widgets (card → counter) |
| `trail(gui, {count?, lag?, transparency?})` → stop | frame | ghost copies following a moving widget (minigame needle) |
| `cameraShake(amplitude?, time?)` → stop | render step | gentle translation-only shake (Legendary/Mythic) |
| `fadeOut(gui, time?)` | timers | every background/text/stroke under `gui` to transparent |
| `setCandy(root, token \| swatch \| Color3)` | — | recolour a candy (states, toast kinds, base colour) |
| `fitStrokes(root)` → unbind | 2 conns | see 6.2 |
| `sound(name, volume?)` | — | "click", "tick", "pop", "swoosh", "splash" (built-in rbxasset sounds) |
| `scaleOf(gui)`, `faceOf(root)`, `tween(…)`, `stagger(items, gap?, fn)`, `sequence(colors)`, `sampleColors(colors, k)`, `lighten`, `darken`, `schedule(step, cleanup?)` → stop, `activeJobs()` | — | helpers; `scaleOf` returns the shared UIScale "FxScale" (FishingController uses the same one) |

### 6.5 Rules for the next agents

- Build widgets with Theme (candy / candyButton / pill / panel / label / icon) and animate with
  UiFx — no hand-rolled colours or tweens; new colours go into UIConfig.
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
- Recipes. Catch card: `rays(raysHolder, {colors = UIConfig.Rarity[r].Rays})` in a transparent
  holder behind the card, `popIn(card, {rotate = -6})`, `shine(card)` after 0.3 s, `confetti(hud,
  {count = Rarity[r].ConfettiCount, colors = Rarity[r].Confetti})`, `countUp(priceLabel, 0, value)`,
  `stamp(mutationBadge)`, Legendary/Mythic: `flash(hud)` + `cameraShake()`; on close `flyTo(hud,
  card, counter, {onArrive = function() UiFx.bump(counter) end})`. Action button:
  `Theme.candyButton(…, "Sky", {Radius = 0.5, Square = true})`, `setCandy` per state,
  `glowRing(button, {loop = true})` while it matters, `shineLoop` when idle, `ripple` on tap.
