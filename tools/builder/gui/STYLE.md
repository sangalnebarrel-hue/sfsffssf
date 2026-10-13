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
