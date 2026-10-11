# World v3 — «Остров Рыбаков» (voxel atoll) — design contract

This file is the contract every builder module follows. Numbers here are mirrored in
`src/ReplicatedStorage/Shared/Config/MapConfig.luau` (v3); builders read them from the cfg
argument and fall back to the values below.

## 1. The look: bright voxel "simulator" style

Target: the look of top Roblox simulators — *Steal a Brainrot*, *Grow a Garden*, *Steal an
Egg*. Bright, saturated, clean, chunky, instantly readable. **Not** realistic.

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
* **Colour.** Saturated, bright, warm. Every structure has a strong main colour + a contrasting
  trim colour + a light detail colour. Two or three shades of the same hue give the "voxel
  shading" (e.g. leaves: dark / mid / light blocks). Avoid greys and browns that are dark or
  dull — dark colours only for small contrast details (eyes, windows' frames, outlines).
* **Chunky + exaggerated.** Thick posts, big signs with big text, oversized fish statues,
  exaggerated proportions (lamp posts with big cube lanterns, mushrooms with fat caps).
* **Readable signage.** Shops and bases carry big `SurfaceGui` signs (Font: `Util.FONT`
  Nunito ExtraBold, Cyrillic text, `TextScaled`, white text with a dark `UIStroke` or dark text
  on a light board).

Shared palette (use `Props.Colors`, keep names):

| name | RGB | use |
|---|---|---|
| GrassTop / GrassTop2 / GrassTop3 | 104,214,72 / 88,198,62 / 124,226,86 | ground caps, lawns |
| Dirt / DirtDark | 170,116,70 / 136,90,56 | ground sides, soil |
| Sand / SandDark / SandWet | 255,228,152 / 236,200,124 / 240,212,140 | beaches |
| Stone / StoneDark / StoneLight | 158,166,180 / 120,128,144 / 196,202,212 | cliffs, rocks, paving |
| Snow | 248,252,255 | peak caps |
| Wood / WoodDark / WoodLight | 204,138,78 / 150,94,52 / 236,184,120 | planks, posts, decks |
| Leaf1 / Leaf2 / Leaf3 | 62,176,64 / 88,204,72 / 132,228,92 | foliage shading |
| Pine1 / Pine2 / Pine3 | 36,140,84 / 50,166,96 / 76,192,110 | conifers |
| Blossom1 / Blossom2 | 255,150,200 / 255,190,225 | cherry trees |
| Autumn1 / Autumn2 | 255,150,40 / 255,196,60 | autumn trees |
| Red / Orange / Yellow / Lime / Cyan / Blue / Purple / Pink | 255,72,72 / 255,148,40 / 255,212,50 / 156,236,60 / 40,216,224 / 64,150,255 / 168,96,255 / 255,104,184 | accents |
| White / Cream | 252,252,250 / 255,244,220 | trims |
| Glass | 150,230,255 | aquariums, windows |

Lighting (build.luau): sunny ~14:00, high brightness, light-blue atmosphere with low haze,
ColorCorrection saturation ≈ +0.25, bloom for neon. Terrain water is turquoise.

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
| HubRadius | 150 | hub island waterline |
| HubPlazaRadius | 124 | hub flat ground (GroundTop) radius |
| LagoonRadius | 296 | ring shore waterline |
| LagoonDepth | 14 | deepest lagoon bed (y = −14) |
| BeachWidth | 12 | sand (y = 2) from LagoonRadius to the promenade |
| PromenadeRadius | 312 | inner edge of the promenade ring = base slot radius |
| PromenadeWidth | 18 | promenade from r 312 to 330 |
| BaseCount / BaseAngleOffset | 8 / 22.5 | base angles 22.5, 67.5, … |
| BaseRadius | 312 | slot position radius (= PromenadeRadius) |
| PlotFront / PlotDepth / PlotHalfWidth | 18 / 150 / 68 | plot rectangle in base-local space |
| PierLength / PierHalfWidth | 92 / 22 | pier corridor in base-local space (incl. end platform) |
| BridgeAngles / BridgeWidth | {0,90,180,270} / 18 | bridges hub ↔ promenade |
| RingOuterRadius | 640 | mean outer coastline |
| OceanHalf / OceanDepth | 1400 / 24 | ocean square half-size / bed depth |
| BoundaryRadius | 780 | invisible wall ring in the ocean |

### Base-local frame (BaseTemplate)

The slot part sits at r = BaseRadius (312, the lagoon-side edge of the promenade), y =
GroundTop, and its **−Z faces the lagoon**. The template's `Root` (PrimaryPart) is at the
origin of this frame; `y = 0` is GroundTop.

```
 lz = 168  ─────────── plot back edge (hills behind)
           |  house / garden / campfire          |
 lz ≈ 120  |                                     |
           |  AQUARIUM: big tank + 12 slot       |   x = −68 … +68
           |  pedestals, dog + doghouse          |
 lz ≈ 50   |                                     |
           |  front yard: spawn pad, flag+sign,  |
           |  siren tower                        |
 lz = 18   ──── big entrance gate (front) ───────
 lz 0..18      public PROMENADE (built by Map — template places nothing here)
 lz 0 … −92    the base's pier (width ≤ 2·22) over the beach (y = −2 local) and water
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
* `Alarm.Lamp` (BasePart, Neon when lit), `Dog` (Model with PrimaryPart)
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
| `tools/builder/Map.luau` | map | assembles Map: slots, ground, hub, bridges, promenade, landmarks, nature, lagoon/ocean decor, boundaries |

Builder conventions (unchanged): deterministic (no `math.random`, seeds only), anchored parts
via `Util.part`, `CanTouch = false` by default, foliage/tiny details `CanCollide = false` and
`CastShadow = false`, attachments placed with `CFrame` (never `.Position` — Lune drops it),
models' pivots via `WorldPivotData`/PrimaryPart, part budgets respected, no PointLight shadows,
PointLight Range ≤ 16.

Part budgets (runtime total target ≤ 15 000): ground ≤ 4 000, 8 bases × ≤ 450, hub ≤ 1 800,
bridges + promenade ≤ 1 200, nature ≤ 2 500, landmarks + islets + lagoon decor ≤ 1 500.

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
| `world.landmarks.Windmill` | `{ angle, radius, x, z, hillRadius = 84, topRadius = 18, top = 36 }` — climbable ziggurat, flat meadow top |
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

* **Hub (r < 150)** — the heart of the map, seen from every base across the lagoon: a big
  bright village plaza. Four avenues from the bridge landings (θ = 0/90/180/270, decks land at
  r ≈ 118–124) meet at a central landmark (giant fountain with a golden fish / a tall
  lighthouse). The three shops sit between avenues, each a big colourful building with a
  huge sign and a blocky shopkeeper: `Shop` (rods), `FishMarket` (sell fish), `Workshop`
  (upgrades); plus a Ferris wheel, food stalls, benches, lamps, flower beds, bunting, palms
  on the beach ring and a small harbour with boats. `HubSpawn` (SpawnLocation) near the centre.
* **Bridges** — 4 chunky voxel bridges with arches at both ends.
* **Promenade (r 312–330)** — plank/stone ring walk with lamps, benches, flower boxes and
  bunting; gaps at piers (θ = base angle ± 5°) and bridge landings.
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
