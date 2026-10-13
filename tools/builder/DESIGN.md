# World v3 «Остров Рыбаков» (voxel atoll), art direction v4 — design contract

This file is the contract every builder module follows. Numbers here are mirrored in
`src/ReplicatedStorage/Shared/Config/MapConfig.luau` (v3); builders read them from the cfg
argument and fall back to the values below.

## 1. The look: rich, natural voxel island (art direction v4)

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
* **Materials.** `SmoothPlastic` for almost everything. `Neon` for glowing accents (lamps,
  signs' rims, siren, magic). `Glass` (Transparency 0.4–0.6) for aquariums/windows.
  `WoodPlanks`/`Brick`/`Cobblestone` textures are NOT used — colour carries the material.
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

Lighting (build.luau): sunny 14:30, Brightness 2.3 with ExposureCompensation -0.1, warm sun
(ColorShift_Top 255,236,208), soft slightly cool sky fill (Ambient 130,124,118, OutdoorAmbient
140,142,152, EnvironmentDiffuseScale 0.5), light atmosphere (Density 0.16, Haze 0.05),
ColorCorrection saturation +0.1 / contrast +0.08, Bloom 0.35 (threshold 2.2, only Neon). Terrain
water (36,156,186), transparency 0.55. Mountains are cool blue slate (Palette Slate*), snow sides
pale blue.
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
* `Flag.Pole.SignAttachment.OwnerSign.{OwnerLabel, BaseLabel}` (BillboardGui TextLabels)
* any number of extra `OwnerLabel` / `BaseLabel` TextLabels elsewhere (e.g. the gate sign):
  BaseService updates **all** TextLabels with those names
* `Accent = true` attribute → painted with the base colour; optional number attribute
  `AccentShade` in [−1, 1]: > 0 lerps towards white by that amount, < 0 towards black.

## 3. Builder modules and who owns what

| file | owner | returns |
|---|---|---|
| `tools/builder/VoxelWorld.luau` | core | ground heightfield, reserved zones, landmark sites, water bake |
| `tools/builder/Ground.luau` | core | greedy-meshed ground parts (`Workspace.Map.Ground`) |
| `tools/builder/Props.luau` | props | voxel prop library (see its header) |
| `tools/builder/BaseTemplate.luau` | template | `ServerStorage.BaseTemplate` |
| `tools/builder/Hub.luau` | hub | `Workspace.Map.Hub` |
| `tools/builder/Map.luau` | map | assembles Map: slots, ground, hub, bridges, promenade, landmarks, nature, lagoon/ocean decor, boundaries; prints the dressing budget |
| `tools/builder/MapKit.luau` | map | shared helpers: seeded rng, Props call, local-frame block builder, signs, lights, claims, stairs over the voxel ground, cheap lamp / flower bed |
| `tools/builder/Promenade.luau` | map | `Map.Bridges` (4 × Props.bridge) and `Map.Promenade` (paving, railing with gaps, lamps, bunting, benches, flower boxes, path billboards) |
| `tools/builder/Gateways.luau` | map | `Map.Gateways` — 4 themed plazas (arch + sign, centrepiece, stall, notice board, photo frame, flower beds) |
| `tools/builder/Landmarks.luau` | map | `Map.Landmarks` — waterfall (stream, cliff stairs, lookout), windmill (tulip terraces, stairs, fence), giant tree, peaks |
| `tools/builder/Coast.luau` | map | `Map.Lagoon`, `Map.Ocean` (islets, shipwreck, rock arch, whale, far sailboats), `Map.Sky` (clouds) |
| `tools/builder/Nature.luau` | map | `Map.Nature` — groves by noise + visibility within the part budget left over by the others |

Builder conventions (unchanged): deterministic (no `math.random`, seeds only), anchored parts
via `Util.part`, `CanTouch = false` by default, foliage/tiny details `CanCollide = false` and
`CastShadow = false`, attachments placed with `CFrame` (never `.Position` — Lune drops it),
models' pivots via `WorldPivotData`/PrimaryPart, part budgets respected, no PointLight shadows,
PointLight Range ≤ 16.

Part budgets (runtime total target ≈ 16 000, plus fish models later): ground ≤ 4 000 (column
caps, bodies, cliff strata, six mountains), 8 bases × ≤ 940, hub ≤ 2 200, map dressing
(everything in `Workspace.Map` except Ground and Hub) ≤ 6 900 parts and 40 PointLights, of which
Nature gets at least 2 500: Map.luau builds Nature last with whatever is left and fails the
build when a cap is exceeded or Nature falls short.

Spinning models: any Model under `Workspace.Map` with a number attribute `Spin` (degrees per
second) is turned about its pivot's LookVector by the client (AmbientController); child Models
with `KeepUpright = true` stay level.

## 4. Preview

`lune run tools/build.luau <in> <out>` → `lune run tools/preview/export_parts.luau <out> parts.json`
→ `python3 tools/preview/render.py parts.json --out-dir DIR [--terrain water.bin] --zoom x,z,r,az`.
Read the PNGs and judge them against section 1. Iterate until it looks like a polished
simulator map, not a prototype.

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
* **Lagoon** — sailboats, rowboats, buoys, lily pads near shores.
* **Ocean** — islets decorated (palms, a lighthouse, shipwreck, rock arch), a whale, voxel
  clouds in the sky.
