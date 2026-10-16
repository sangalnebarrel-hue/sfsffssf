# World v3 «Остров Рыбаков» (voxel atoll), art direction v5 (v4 + LEGO studs) — design contract

This file is the contract every builder module follows. Numbers here are mirrored in
`src/ReplicatedStorage/Shared/Config/MapConfig.luau` (v3); builders read them from the cfg
argument and fall back to the values below.

## 1. The look: rich, natural voxel island (art direction v4) built from LEGO (v5)

Target: the charm and readability of top Roblox simulators (*Grow a Garden*, *Steal a
Brainrot*) — chunky blocks, clear shapes, sunny — but with a **calm, harmonious, natural
palette**: a well-kept fishing village on a green island, not a candy shop. v3 was too loud
(lime lawns, neon team colours on whole plots, rainbow everything, +25 % saturation in the
grading); v4 fixes that. All colours come from `tools/builder/Palette.luau`.

Colour rules (measured by `tools/preview/palette_lint.py`, "loud" = HSV S > 0.6 and V > 0.8):

* **Large surfaces are calm**: lawns, soil, rock, sand, water, walls, roofs, decks, paving,
  fences use Palette materials (GrassTop*, Dirt, Stone*, Sand*, Wood*, Plank, Plaster, Brick,
  Cobble, Roof*). No loud part bigger than ~400 studs² of visible area.
* **Accents are small**: flowers, flags, awnings, trims, lanterns, signs, boat paint. The whole
  map sits in a 0.4–5 % loud-area band.
* **Team colour on a plot** (the base's own colour, `Accent`) only on the flag, the roof (or roof
  trim), awnings/banners, the gate sign and a few small trims — never on lawns, fences, decks,
  platforms or whole walls.
* **One building = one wall colour + one roof colour + one trim colour** (+ wood/stone).
* **Neon** only for lamp cores, crystals and glow details — small and few.
* **No decorative people or animals** (no shopkeepers, scarecrows, snowmen, dogs on display).
  The base dog is a gameplay upgrade (stage 4): its model exists but stays invisible until bought.
* Lighting is neutral: ColorCorrection saturation ~0, light Bloom (only Neon blooms), soft cool
  shadows, a bit of atmospheric haze for depth.

Richness: buildings are real voxel architecture — a stone or wooden base course, framed walls,
windows with frames and sills, doors with steps, roofs with overhangs, ridge and chimney, porches
with posts, signs, flower boxes, lanterns — not boxes with a lid. Plots are designed spaces with
paths, fences, beds, a work area, places to sit, lights.

Rules:

* **Blocks first.** Natural things (ground, hills, rocks, foliage, tree trunks, clouds) are made
  of axis-aligned Block parts on a coarse grid. No spheres, no wedge foliage, no cylinders for
  trees. Cylinders only for thin round things (poles, pipes, wheels, barrels, lamp posts,
  bottles); balls only for tiny round details (buoys, eyes, lamp bulbs). Roofs are stepped
  block layers or chunky wedges with a thick trim.
* **Grid sizes.** Prefer dimensions that are multiples of 1 stud (props) / 2 or 4 studs
  (buildings) / 8 studs (ground). Rotations: buildings/props facing any angle is fine, but a
  prop's own parts stay orthogonal to each other.
* **Materials.** Builders make `SmoothPlastic` for almost everything. `Neon` for glowing accents
  (lamps, signs' rims, siren, magic). `Glass` (Transparency 0.4–0.6) for aquariums/windows.
  `WoodPlanks`/`Brick`/`Cobblestone` textures are NOT used — colour carries the material.
* **LEGO studs (art direction v5, like *Steal a Brainrot*).** One build post-pass,
  `tools/builder/Studs.luau` (run by `tools/build.luau` on `Workspace.Map` and
  `ServerStorage.BaseTemplate`, not on `Assets`), turns block parts into LEGO bricks with the
  engine's own surfaces: **Plastic + `Studs` on the face pointing world-up**, the other five
  `Smooth` (surfaces render only on Plastic); **`Inlet`** (LEGO's hollow underside) on the face
  pointing down **only where a builder asks** — attribute `StudsBottom = true` on the part or an
  ancestor (the market arcades' ceilings, the windmill room's ceiling) — and never on foliage:
  canopies, roofs and decks seen from below show no rows of dark holes (v3 fix W7). No textures,
  no extra parts or draw calls.
  * **Studded:** opaque (Transparency ≤ 0.02) SmoothPlastic/Plastic `Part`s (Block shape, also
    `SpawnLocation`) with an axis pointing straight up and an up face of at least 2 × 2 studs —
    ground caps, lawns, sand, decks, floors, paths and paving (variant A), flat roof tops and
    ridges, foliage tops, tables, benches and planters of 2 × 2 and up. A face under 6 studs on
    both sides must be whole studs (± 0.1): small props get no cut studs.
  * **Smooth:** walls and other vertical faces, wedges (LEGO slopes are smooth), cylinders and
    balls, tilted parts, small props (< 2 studs, or fractional under 6), Neon, Glass, transparent
    parts, water / foam / pools / clouds (by name), `Map.Sky`, `Map.Boundaries`,
    `Ground.Underwater` (the seabed), `BaseSlots`, runtime FX parts, rods, bobbers and fish.
  * **Builders' controls:** attribute `Studs = false` on a part or model = smooth (hard opt-out);
    `Studs = true` = studded even with a water-like name (geometry rules still apply). Knobs in
    Studs.luau: `PATHS_AS_TILES` (variant B: paving, avenues, plaza, bridges, walks stay smooth
    LEGO tiles) and `FOLIAGE`.
  * **Coplanar tops:** two overlapping up faces closer than 0.05 (`Studs.COPLANAR_EPS`: a phone's
    depth buffer cannot tell them apart from 150+ studs) with different stud grids (or studs on
    flat) shimmer, so the post-pass moves one top 0.06 (`Studs.RAISE`; the smaller up first;
    never a gameplay part, never onto or past another layer; ~245 parts, 0.06–0.12) or, when
    there is no room, makes that paving piece a flat SmoothPlastic tile (none today). Builders
    keep layered decor ≥ 0.06 apart (v3 fix W3: the hub star's square turned 45° is a flat tile
    0.06 under the other one; every other promenade flag stands 0.1 higher; the gateway plazas'
    rings, walks, medallions and compass, the pond rims and the hub's side walks step 0.06; a
    `disc` of overlapping rects has whole-stud half extents, so its pieces' grids line up);
    same-colour aligned grids may stay level.
  * **Hero faces on whole studs (v3 fix W4):** the surfaces players stand on and look at — the
    base's lawn (135 × 149) and stripes, decks (platform 40 × 21) and full-length plank strips,
    the ring round the fishing spot (7 × 7 round the 5 × 5 mat: one ring of whole studs; the mat
    itself is a smooth tile, `Studs = false`), the display rims (7 × 7), the promenade's flags,
    runner, medallions, coping and sea wall (ring pieces rounded up per segment), the hub's star,
    rays, ring and avenue runners — have whole-stud sides: no cut half-studs along an edge. The
    build fails on a hero face off whole studs (`Studs.fractionalFaces`, build.luau) and reports
    how many other big faces (trees, props) are not.
  * **Stud pitch is the engine's (1 stud)**; the grid is assumed to start at a face corner (the
    previews do; to verify in Studio): whole-stud sizes and offsets keep neighbouring grids in
    line, ring segments and fractional parts show a seam.
  * **Runtime parts** (`src/`): `Instance.new("Part")` is Plastic with Studs on top by default —
    every part made at runtime sets `Material` explicitly (FX: `SmoothPlastic`), checked by
    `tests/studs.test.luau`.
* **Colour.** See the v4 colour rules above: calm materials, small accents. Two or three
  shades of the same hue give the "voxel shading" (e.g. leaves: dark / mid / light blocks).
* **Chunky + exaggerated.** Thick posts, big signs with big text, oversized fish statues,
  exaggerated proportions (lamp posts with big cube lanterns, mushrooms with fat caps).
* **Readable signage.** Shops and bases carry big `SurfaceGui` signs (Font: `Util.FONT`
  Nunito ExtraBold, Cyrillic text, `TextScaled`, white text with a dark `UIStroke` or dark text
  on a light board).

Shared palette: `tools/builder/Palette.luau` (also exposed as `Props.Colors`, same names).
Materials: GrassTop/GrassTop2/GrassTop3, Dirt/DirtDark, Sand/SandDark/SandWet,
Stone/StoneDark/StoneLight, Snow, Wood/WoodDark/WoodLight, Plank, Plaster/PlasterShade, Brick,
Cobble/CobbleDark, RoofRed/RoofTerracotta/RoofBlue/RoofGreen/RoofSlate/RoofBrown, foliage
(Leaf*, Pine*, Palm*, Mint*, BirchLeaf*, Blossom*, Autumn*), Rock*, Straw, Bark*. Accents (small
parts only): Red, Orange, Yellow, Lime, Cyan, Blue, Purple, Pink, Gold, White, Cream, Navy, Iron.
Lists: Flowers, BoatPaint, Festive. Light: Glow, LightColor, Flame*.

Studs and colour: the stud pattern averages to the face colour (colourfulness of the views
unchanged, 78–104); pale caps stay below white (snow cap 222,230,242) so lit studs do not clip.

Lighting (build.luau): sunny 14:30 but NOT overexposed (user feedback «пересвеченная»):
Brightness 1.7, ExposureCompensation -0.3, sun ColorShift_Top (236,220,196), soft fill (Ambient
96,94,100, OutdoorAmbient 112,116,130, EnvironmentDiffuseScale 0.35, specular 0.2 — a little
sky gloss on the plastic studs, v3 WOW-7; Studio check vs 0.08 / 0.45 at Graphics 1 and 3), light
atmosphere (Density 0.16, Haze 0.05), ColorCorrection saturation +0.12 / contrast +0.12 /
brightness -0.04, Bloom 0.15 (threshold 2.6, only Neon). Pale materials (sand, plaster,
limestone, flagstone, cream, snow) stay at value <= ~0.88. Terrain water (36,156,186), T 0.55.
Mountains are cool blue slate (Palette Slate*), snow sides pale blue.
Colour band: Hasler colourfulness of the player/overview renders 75–105
(`tools/preview/colourfulness.py`; v3 was 115–136 = garish, v4 round 1 56–76 = dull); palette_lint loud area 0.4–5 % of the map (bright accents exist, nothing big is
candy; the hub's golden fish and the bases' team-colour roofs are the big identity accents), grey <= 9 %.
Team colours alternate warm/cool around the ring (BaseConfig.Colors); hub and gateway buildings
avoid saturated team hues on big roofs (slate, brown, straw, wood) so every sector's strongest
roof colour is its own base.

## 2. The world (top view, studs; angle θ → (r·sin θ, y, r·cos θ), θ = 0 is +Z)

```
                 ocean (Terrain water to ±OceanHalf, islets far out)
           outer coast ~ r 640 (noisy, beaches + cliffs)
        hills/forest  r 480..640, landmarks between plots (r 330..560)
     8 big plots  r 330..480  (BaseAngleOffset 22.5° + k·45°)
   promenade ring r 312..330  (flat, GroundTop)
  beach ring     r 296..307  (sand, y = 2)
 lagoon water    r 150..296  (Terrain water, bed −2 … −14)
hub island       r < 150     (plaza flat at GroundTop for r < 124, sand y = 2 to r 150)
4 bridges at θ = 0/90/180/270 from the hub plaza to the promenade
```

| key | value | meaning |
|---|---|---|
| WaterTop | 0 | water surface everywhere (lagoon + ocean) |
| GroundTop | 4 | plots, promenade, hub plaza |
| CellSize | 8 | ground voxel column width (studs); heights are multiples of 2 |
| HubRadius | 185 | hub island waterline |
| HubPlazaRadius | 158 | hub flat ground (GroundTop) radius |
| LagoonRadius | 296 | ring shore waterline |
| LagoonDepth | 14 | deepest lagoon bed (y = −14) |
| BeachWidth | 12 | sand (y = 2) from LagoonRadius to the promenade |
| PromenadeRadius | 312 | inner edge of the promenade ring = base slot radius |
| PromenadeWidth | 18 | promenade from r 312 to 330 |
| BaseCount / BaseAngleOffset | 8 / 22.5 | base angles 22.5, 67.5, … |
| BaseRadius | 312 | slot position radius (= PromenadeRadius) |
| PlotFront / PlotDepth / PlotHalfWidth | 18 / 150 / 68 | plot rectangle in base-local space |
| PierLength / PierHalfWidth | 72 / 22 | pier corridor in base-local space (incl. end platform) |
| BridgeAngles / BridgeWidth | {0,90,180,270} / 18 | bridges hub ↔ promenade |
| RingOuterRadius | 600 | mean outer coastline |
| OceanHalf / OceanDepth | 1400 / 24 | ocean square half-size / bed depth |
| BoundaryRadius | 780 | invisible wall ring in the ocean |

### Base-local frame (BaseTemplate)

The slot part sits at r = BaseRadius (312, the lagoon-side edge of the promenade), y =
GroundTop, and its **−Z faces the lagoon**. The template's `Root` (PrimaryPart) is at the
origin of this frame; `y = 0` is GroundTop.

```
 lz = 168  ─────────── plot back edge (hills behind)
           |  cottage + smokehouse, garden, yard  |
 lz ≈ 120  |                                     |
           |  AQUARIUM: big tank + 12 slot       |   x = −68 … +68
           |  pedestals, doghouse (dog: stage 4)  |
 lz ≈ 50   |                                     |
           |  front yard: spawn pad, flag+sign,  |
           |  siren tower                        |
 lz = 18   ──── big entrance gate (front) ───────
 lz 0..18      public PROMENADE (built by Map — template places nothing here)
 lz 0 … −72    the base's pier (width ≤ 2·22) over the beach (y = −2 local) and water
               (y = −4 local), end platform with the fishing spot
```

Ground under the plot is flat GroundTop grass (x ±76, lz 10..176 incl. margin); the template
lays its own floor/paths/borders on top (slab tops at y ≈ 0.2; nothing coplanar with y = 0).

### Names the server code relies on (BaseService) — keep exactly

* `Root` (PrimaryPart), `SpawnPad` (BasePart, −Z = facing on spawn), `FishingSpot` (BasePart)
* `Tank` (Model) with `Tank.Glass` (BasePart) and `Tank.Glass.PromptAttachment`
* `Tank.Slots.Slot_1 … Slot_12` (Models, attribute `SlotIndex`), each with `Pedestal`
  (BasePart), `Display` (glass BasePart), `Display.FishPoint` (Attachment where the fish
  model will float), `Pedestal.PromptAttachment` (Attachment for steal/collect prompts) and
  `Pedestal.LabelGui.Label` (SurfaceGui + TextLabel on the front, text "Пусто")
* `Alarm.Lamp` (BasePart, Neon when lit), `Dog` (Model with PrimaryPart; invisible, attribute
  `Unlocked = false`, until the stage-4 dog upgrade shows it)
* `Flag.Pole.SignAttachment.OwnerSign.{OwnerLabel, BaseLabel, YoursLabel}` (BillboardGui
  TextLabels; `YoursLabel` «ТВОЯ БАЗА!» is hidden — only the owner's own client shows it)
* any number of extra `OwnerLabel` / `BaseLabel` TextLabels elsewhere (e.g. the gate sign):
  BaseService updates **all** TextLabels with those names
* `Accent = true` attribute → painted with the base colour; optional number attribute
  `AccentShade` in [−1, 1]: > 0 lerps towards white by that amount, < 0 towards black.

### Per-base variants and the micro-kits (v3 detail)

* **Variants:** a template instance (Model or BasePart) with number attributes `Variant = k` and
  `VariantOf = n` is kept only on the bases whose index `i` gives `(i − 1) % n + 1 == k`;
  BaseService destroys it on the others right after cloning (before painting), and
  `tools/preview/export_parts.luau` mirrors the rule. Today: `PierKit.Scenes` — 4 little scenes
  on the platform's free front-right deck (crab pots, a net heap with a float basket, flower boxes
  on the front rails, an anchor with oars), so bases 1/5, 2/6, 3/7, 4/8 differ (and every base
  has its own Accent colour on the tackle box, pennants, roof flag and bird-house roof). Names
  the server relies on are never inside a variant.
* **`PierKit`** (BaseTemplate.buildPierDressing, ~68 parts + one scene): lanterns on the two front
  posts framing the cast (Neon, no PointLight), battens across the walkway, rope coils, hung buoys,
  potted plants at the root, a pennant string across the walkway's end, a tackle box (Accent) and
  a stool beside the spot, fish traps, a net with floats over the right rail, drying fish, a basket
  of the catch, a crab pot on a line, algae collars on the platform piles, a windsock, a roof
  pennant and a shell wind chime on the shelter. **`YardKit`** (25 parts): a wheelbarrow, a
  watering can, an (empty) bird house, stepping stones, grass tufts. Roof tile courses on the
  house, smokehouse and tackle shed (`RoofCourse`, darker Accent), plank strips in three tones.
* **Rules for every kit part** (tests/stage1_bases.test.luau): decor (CanCollide, CanQuery,
  CanTouch, CastShadow all false); nothing in the walkway's middle lane (|x| ≤ 4.5); nothing above
  local y 7 within 13 studs of `FishingSpot`; nothing over 1.5 tall in the follow camera's sector
  behind the player (|x| ≤ 7, z −67 … −55); nothing above y −4.6 (the water) in the cast clear
  zone (x −6 … 16, z −72 … −115); layered decor ≥ 0.06 above the face below (studs).
* **The shelter (`Pavilion`)** stands at the platform's back-left corner (posts x −18.8 / −12.5,
  z −60.5 / −51 base-local): from the default follow camera behind the spot (12.5 studs back, 18°
  down) its posts are out of a phone's frame (tests/stage1_bases.test.luau), only the roof's
  corner shows top-left; the rod rack stands under it behind the bench (v3 fix W1).
* **Signs:** every SurfaceGui of a base has a `MaxDistance` (120; the 12 pedestal labels 60, at
  30 px per stud); the map's signs 250 (`Kit.sign` 600 for the big boards). The owner sign over
  the flag (UI v5 «Симулятор», like the reference's «МАГАЗИН СЛЕДОВ» / «БЕСПЛАТНО!») is billboard
  words with NO plate (smooth letters straight over the world; the LEGO look is the map's):
  Montserrat Heavy, a white → colour `Fill` UIGradient and a THIN round `Outline` UIStroke in the
  look's dark shade, like the reference's 1.5–2 px on a 33 px cap (2 px for the owner's line and
  «ТВОЯ БАЗА!», 1.5 for the base name; the gate board 3 / 2.5 at 32 px per stud) — the owner's
  name in white or «СВОБОДНО!» in `UIConfig.BillboardGreen` (a free
  base), under it the base's name in CAPS in its own swatch (`UIConfig.BaseSwatches`, painted by
  BaseService), over them «ТВОЯ БАЗА!» in green on the owner's own client (the three rows stay
  inside the billboard's frame, room left for the outline); 10 × 3.2 studs + 150 × 52 px,
  `MaxDistance` 500 (readable across the lagoon; the GUI previews' world scenes draw them). The gate's name board uses the same
  letters (v3 fix WOW-5, F4; UI v5; tools/builder/gui/STYLE.md §3 «Words in the world»).

## 3. Builder modules and who owns what

| file | owner | returns |
|---|---|---|
| `tools/builder/VoxelWorld.luau` | core | ground heightfield, reserved zones, landmark sites, water bake |
| `tools/builder/Ground.luau` | core | greedy-meshed ground parts (`Workspace.Map.Ground`) |
| `tools/builder/Props.luau` | props | voxel prop library (see its header) |
| `tools/builder/BaseTemplate.luau` | template | `ServerStorage.BaseTemplate` |
| `tools/builder/Hub.luau` | hub | `Workspace.Map.Hub` |
| `tools/builder/Map.luau` | map | assembles Map: slots, ground, hub, bridges, promenade, landmarks, nature, lagoon/ocean decor, boundaries; prints the dressing budget |
| `tools/builder/MapKit.luau` | map | shared helpers: seeded rng, Props call, local-frame block builder, signs, lights, claims, stairs over the voxel ground, cheap lamp / flower bed, `Kit.sway` (moving details), `Kit.obstacles` (what the late kits keep off) |
| `tools/builder/Promenade.luau` | map | `Map.Bridges` (4 × Props.bridge) and `Map.Promenade` (paving, railing with gaps, lamps, bunting, benches, flower boxes, path billboards; `Promenade.buildDetails` after Nature: coping bollards, hanging baskets, bins, arrow signposts) |
| `tools/builder/Gateways.luau` | map | `Map.Gateways` — 4 themed plazas (arch + sign, centrepiece, stall, notice board, photo frame, flower beds) |
| `tools/builder/Landmarks.luau` | map | `Map.Landmarks` — waterfall (stream, cliff stairs, lookout), windmill (tulip terraces, stairs, fence), giant tree, peaks |
| `tools/builder/Coast.luau` | map | `Map.Lagoon`, `Map.Ocean` (islets, shipwreck, rock arch, whale, far sailboats), `Map.Sky` (clouds) |
| `tools/builder/Nature.luau` | map | `Map.Nature` — groves by noise + visibility within the part budget left over by the others |
| `tools/builder/Studs.luau` | core | LEGO studs post-pass over Map and BaseTemplate (`apply`, `resolveCoplanar`, `coplanarPairs`) |
| `tools/builder/Shore.luau` | map | `Map.Shore` (built after Nature, keeps off every part): surf `Foam` and `WetSand` strips along every sand/water voxel edge (ring + hub), beach stories (sandcastle, parasol, driftwood, pinwheel, bottle), finds, rocks and reeds, float lines either side of every base's fishing water, drifting cargo, lilies, kelp and sunken chests (`Underwater`) |
| `tools/builder/HubDetails.luau` | map | `Map.Hub.Details` (after Nature): café tables, flower barrels, arrow signposts on the hub plaza |

Builder conventions (unchanged): deterministic (no `math.random`, seeds only), anchored parts
via `Util.part`, `CanTouch = false` by default, foliage/tiny details `CanCollide = false` and
`CastShadow = false`, attachments placed with `CFrame` (never `.Position` — Lune drops it),
models' pivots via `WorldPivotData`/PrimaryPart, part budgets respected, no PointLight shadows,
PointLight Range ≤ 16.

Part budgets (v3; StreamingEnabled is off, so every phone holds every part from the join on;
numbers in `MapConfig.PartBudget`, enforced by `tools/build.luau`):

| what | cap | now |
|---|---|---|
| **static** (Workspace.Map + 8 × one base with its own variant) | **24 000** | ≈ 23 470 |
| **runtime peak** = static + reserve (stage-3 tank fish 1 920, ambient life 140, characters 260, fishing FX 400) | **26 500** | ≈ 26 190 |
| ground (column caps, bodies, cliff strata, mountains) | ≤ 6 000 (test) | 4 068 |
| one base at runtime (`BaseTemplate.BUDGET`) / the template with every variant | 1 060 / 1 090 | 1 055 / 1 071 |
| hub (Hub.luau's own build ≤ 2 900, + HubDetails) | 3 000 | ≈ 2 910 |
| map dressing (everything in `Workspace.Map` except Ground and Hub) | 8 100 parts, 40 PointLights | ≈ 8 060 |
| … of which Nature (built with what the others leave) | ≥ 2 050 | 2 208 |
| … of which the late kits (Promenade details + Shore, after Nature) | 1 200 | ≈ 1 160 |

The kits add no PointLights, no particle emitters and no shadow casters. A builder that needs more
raises its cap here, in its module and in MapConfig deliberately (and checks the phone budget
above); Map.luau fails the build when a cap is exceeded or Nature falls short.

### Ambient attributes (the contract for the client's ambient motion)

Builders only **mark** what moves; the client animates it (AmbientController + AmbientEngine /
AmbientWind / AmbientWorld / AmbientWater / AmbientCritters),
locally: everything that moves is CanCollide/CanQuery/CanTouch false — enforced by one post-pass,
`tools/builder/Movers.luau` (`Movers.quiet`, run at the end of Map.luau and BaseTemplate.luau),
except the palm trees' trunks (they collide; they sway only 1.2° about the foot, which stays put).
Floats you can stand on (the swim platform, the raft, the fish farms, the houseboats) carry no `Bob`:
still and solid (a bob seen only on one client would carry a child up and down on it while everyone
else sees it still); the base's moored boat bobs and does not collide (v3 fix F2). "Pivot" = a Model's
pivot (its PrimaryPart's CFrame × PivotOffset) or a BasePart's CFrame × PivotOffset. Moving things
are never nested inside another moving model (an inner one is ignored).

| attribute (number unless noted) | on | motion |
|---|---|---|
| `Spin` (°/s) | Model under Workspace.Map | turns about its pivot's LookVector; child Models with `KeepUpright = true` stay level (windmills, Ferris wheel, golden fish, the beach pinwheels) |
| `Bob` (studs), `BobPeriod` (s, default 3) | Model in Workspace.Map or Workspace.Bases | rises and falls and rolls a little about its pivot (boats, buoys, the float lines, drifting crates, lily clusters; never something to stand on) |
| `Sway` (° amplitude), `SwayAxis` (string "X" / "Y" / "Z": the pivot's local axis, default "X"), `SwayPeriod` (s, default 3) | Model or BasePart (parts parented under a swaying part ride on it), in Workspace.Map or Workspace.Bases | swings to and fro about the pivot (the hang point), phase hashed from the pivot position, amplitude × the wind gust (0.6–1.4, gusts travel across the map along the wind): flags and pennants (`Y` about the pole: `Flag.Cloth`, Props.flagPole's `Cloth`, gateway/landmark/nature flags), bunting and festoons (`Z` along the rope), lamp banners and hanging baskets, the pier's pennant string, net, drying fish, hung buoys, wind chime, windsock (`Y`), weathervanes (`Y`, 25°), palm trees (1.2° about the foot), reeds and kelp (about the bed) |
| `Pulse` (transparency amplitude), `PulsePeriod` (s) | Model (every part in it) | transparency breathes around the parts' own value, phase travelling with position (`Map.Shore.Foam`) |
| `Drift` (studs/s) | Model under Map.Sky | circles slowly round the island centre (the clouds) |

Without an attribute (found by name, so builders keep them that way):

| what | rule | motion |
|---|---|---|
| chase lights | `Neon` parts named `…Bulb<n>` / `…Bulbs<n>` (≥ 2 under one parent; inside Spin / Sway models too) | marquee: 2 on / 2 off marching 6 steps a second (2-bulb sets blink in turn), off = Transparency 0.55 (Ferris wheel rim, fair festoon, fair arch) |
| wind | ParticleEmitters named `Smoke`, `Mist`, `Petals`, `Steam`, `Leaves` | `WindAffectsDrag` on (Drag raised to 0.3–0.5 if lower); the client sets `Workspace.GlobalWind` from the gust |
| foam rings | every `Bob` model on the water (pivot within 4 studs of WaterTop) | an oval ring (SurfaceGui) round the hull = parts crossing the waterline (all 8 corners: an upright cylinder float counts), thin ropes / moorings (< 0.35 × > 2.5 studs) and masts left out, hulls under 1.4 studs none; pier `Post`s crossing the water get a round one; the breathing (stroke only) is written only when it changed by 0.05+ (checked 2× a second) |
| waterfall flow | parts `Curtain<i>_<j>` in `Landmarks.Waterfall.Waterfall` | a Beam down the front face (texture streaming down) |
| butterflies | parts named `…Bloom…` (not `…Eye`), ≥ 3 in a 16-stud cell = a flower bed | up to 6 butterflies flutter round the beds nearest the camera |

The engine (AmbientEngine): ONE `RunService.PreRender` connection for all of it, asleep (none) when
nothing is in range. Each item's tier comes from how fast it moves ON SCREEN (studs/s of its fastest
point × pixels per stud at its distance): > 20 Hz needed → every frame, 7.5–20 Hz → a third of the tier
per frame (≈ 20 Hz each), else an eighth (≈ 7.5 Hz); only items in the camera's view (+ radius) are
touched; at most 220 parts moved + properties written per frame on phones (400 on PC) — one
`BulkMoveTo`. Ranges: Sway 250, Pulse 200, Bob 400, chase lights 300, Spin 900 studs, clouds 2500.
Measured (tools/preview/ambient_dump.luau, phone): 120–140 per frame at a fishing spot (peak = the
budget), 20–60 in a yard; RbxSim frame cost 3.6 ms vs 9.6 ms for the old 30 Hz mover (same view).

## 4. Preview

`lune run tools/build.luau <in> <out>` → `lune run tools/preview/export_parts.luau <out> parts.json`
→ `python3 tools/preview/render.py parts.json --out-dir DIR [--terrain water.bin] --zoom x,z,r,az`.
Read the PNGs and judge them against section 1. Iterate until it looks like a polished
simulator map, not a prototype. The exporter writes stud surfaces (Plastic parts only) and the
renderer draws them per pixel (`--no-studs` hides them).

## 5. VoxelWorld API (for Hub/Map decorators)

`local world = VoxelWorld.new(MapConfig)` (built once in `tools/build.luau` and passed as the
third argument to `buildMap(game, cfg, world)`, which passes it on to `buildHub(map, cfg, world)`).

| call | returns |
|---|---|
| `world:heightAt(x, z)` | top y of the ground column under (x, z) (stand props at this y) |
| `world:kindAt(x, z)` | `grass` `meadow` `path` `sand` `shallow` `seabed` `deep` `stone` `snow` `grassRock` |
| `world:surfaceAt(x, z)` | `top, kind, waterTop?` (waterTop = 0 when the column is under water) |
| `world:isWater(x, z)` | column top below WaterTop |
| `world:slope(x, z)` | biggest step to a neighbour column (studs) — 0 on flat ground |
| `world:isReserved(x, z, margin?)` | inside/near hub+lagoon+promenade, plots, gateways, paths, landmark sites |
| `world:toBaseLocal(i, x, z)` | base-local `lx, lz` of base i |
| `world.bases[i]` | `{ index, angle, x, z }` (slot position) |
| `world.gateways[i]` | `{ index, angle, x, z, radius }` flat plazas behind each bridge landing |
| `world.landmarks.Waterfall` | `{ angle, radius (cliff front r), cliffTop = 56, halfWidth = 56, depth = 150, pondR, pondX, pondZ, pondRadius = 30 }` — mesa from r = radius outwards (flat top 56, a 44-high ledge ring along its sides/back), pond (water) at its foot |
| `world.landmarks.Windmill` | `{ angle, radius, x, z, hillRadius = 90, topRadius = 24, top = 36 }` — climbable ziggurat, flat meadow top |
| `world.landmarks.GiantTree` | `{ angle, radius, x, z, plateauRadius = 46, top = 8 }` — meadow plateau one step up |
| `world.landmarks.Peak` | `{ angle, radius, x, z, mountainRadius = 150, top = 116 }` — snowy mountain at the outer coast |
| `world.islets[i]` | `{ angle, x, z, size, height }` — stepped rounded-square islands in the ocean |
| `world:noise(x, y)` | deterministic Perlin noise in about [−1, 1] |

Ground facts: cells are 8 studs; hills/coast/sea are sampled on a 16-stud grid, so terraces are
16-stud blocks with 4-stud steps; plots, promenade, gateways and paths are exactly GroundTop
(4); beaches are y = 2; the lagoon bed is −2 / −6 / −14; the ocean shelf −2 / −8 / −16 / −24.
Radial paths (kind `path`, width 12) run from the promenade to the windmill hill, giant tree,
waterfall pond and the peak's foot.

## 6. What goes where (composition)

* **Hub (r < 185, plaza r < 158)** — the heart of the map, seen from every base across the
  lagoon: a cosy harbour town square. Four avenues from the bridge landings (θ = 0/90/180/270, decks
  land at r ≈ 152) meet at the ~75-stud «Золотая рыбка» tower (stepped fountain with a circling
  golden fish). The three shops (1.2× scale, r ≈ 76, porches on the plaza rim) sit between the
  avenues as real buildings with big signs: `Shop` (rods), `FishMarket` (sell fish),
  `Workshop` (upgrades); a second ring holds the game booth, the stage, food kiosks, a Ferris
  wheel and the harbour boardwalk; palms, huts and a terrace step ring the beach. The view lanes
  from every base to the tower stay open. `HubSpawn` (SpawnLocation) near the centre.
* **Bridges** — 4 chunky voxel bridges with arches at both ends.
* **Promenade (r 312–330)** — plank/stone ring walk with lamps, benches, flower boxes and
  bunting; a sea wall on the lagoon side; gaps at piers (θ = base angle ± 6°) and bridge landings.
* **Gateways (θ = 0/90/180/270, r ≈ 372)** — each a themed plaza: welcome arch + big sign,
  e.g. fish statue, notice board/map, market stall, photo spot.
* **Landmarks (θ = 45/135/225/315)** — Waterfall (falls down the mesa face into the pond,
  stairs to a lookout deck on the mesa), Windmill (on the ziggurat top, flower fields on the
  terraces), Giant tree (treehouse, swing, glowing mushrooms), Peak (flag and lookout on the
  summit, pines on the slopes).
* **Nature** — voxel forests on the hills (pine/oak/cherry/autumn groves by noise), palms
  near the outer beaches, bushes, flowers, rocks, mushrooms. Never on reserved ground.
* **Lagoon** — sailboats, rowboats, buoys, lily pads near shores; surf and wet sand along every
  sand edge (the surf a row of white LEGO plates — dashes ~7 studs, 2.5-stud gaps, two widths,
  the top 0.27 over the water, above the wave crests), beach stories on the ring and hub beaches,
  three big LEGO round floats (1.6 studs, red / white with a band) either side of every base's
  cast lane where the player looks while waiting (base-local x −27 / +28.5, z −84 … −112; v3 fix
  W2, W5), kelp and sunken chests on the slope.
  The **cast clear zone** of every pier (base-local x −6 … 16, z −72 … −115) has nothing above the
  water; nothing of the shore kit within 26 studs of a pier's axis out to z −92 (pier, boat,
  cast).
* **Ocean** — islets decorated (palms, a lighthouse, shipwreck, rock arch), a whale, voxel
  clouds in the sky.
