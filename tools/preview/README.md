# Map preview renderer

Renders PNG previews of the map geometry in a `.rbxl` place file, so the map can be
checked visually without Roblox Studio. Two steps:

1. `export_parts.luau` (Lune 0.11) reads the place and writes every visible part as JSON.
   It also simulates what the server does at runtime (base spawning, see below).
2. `render.py` (Python 3 + numpy + Pillow) draws the JSON as orthographic images, and
   as perspective "player eye" images with sky and distance fog (`--views persp`).

```sh
LUNE=/opt/tools/l11/lune   # Lune 0.11; 0.10.4 cannot read the place

$LUNE run tools/preview/export_parts.luau Place1.rbxl /tmp/preview/parts.json
python3 tools/preview/render.py /tmp/preview/parts.json --out-dir /tmp/preview
```

Smooth terrain (`Workspace.Terrain` voxels) is not a part: add it with `--terrain`, see
[Terrain](#terrain) below.

Output files in `--out-dir`: `top.png`, `iso.png`, `iso2.png`, `zoom_1.png`, `zoom_2.png`, ...
Each image has an info box (view, part counts), a scale bar and an axis legend.
Perspective views (`persp_1.png`, `persp_2.png`, ...) are described in
[Perspective views](#perspective-player-eye-views).

### Previewing one player base (template_preview.luau)

`template_preview.luau` builds a tiny place with only `ServerStorage.BaseTemplate` (from
`tools/builder/BaseTemplate.luau`), one base slot at the origin and a flat stand-in world
(grass, the promenade strip, beach, water), so the base can be iterated on without
generating the whole map. The optional second argument picks the base colour
(`BaseConfig.Colors[index]`). Renders of the current base live in `docs/base/`.

```sh
$LUNE run tools/preview/template_preview.luau /tmp/preview/base.rbxl 3   # 3 = yellow base
$LUNE run tools/preview/export_parts.luau /tmp/preview/base.rbxl /tmp/preview/base.json
python3 tools/preview/render.py /tmp/preview/base.json --out-dir /tmp/preview/base \
    --views iso,zoom --zoom 0,62,100,200 --zoom 0,92,40,200 --zoom 2,-62,42,215
```

## export_parts.luau

```
lune run tools/preview/export_parts.luau <place.rbxl> <out.json> [--no-bases]
```

Exports:

| kind    | what                                                                                  |
|---------|---------------------------------------------------------------------------------------|
| `part`  | every `BasePart` under `Workspace` (not `Terrain`, not under `Camera`), `Transparency < 0.98` |
| `water` | parts under `Workspace.Map.Lake.WaterVolumes` or `Workspace.Map.Water` (edit-mode stand-ins for Terrain water, filled at runtime). Exported even when invisible. |
| `base`  | virtual copies of `ServerStorage.BaseTemplate`, one per slot (see below)               |

Runtime base simulation (mirrors `BaseService`): for every child `BasePart` of
`Workspace.Map.BaseSlots` with a numeric attribute `Index` (sorted by `Index`), every
`BasePart` of the template is placed at

```
worldCF = slot.CFrame * (PrimaryPart.CFrame * PrimaryPart.PivotOffset):Inverse() * part.CFrame
```

which is what `Model:PivotTo(slot.CFrame)` does. Template parts with attribute
`Accent == true` get the base colour `Colors[Index]` (shaded by the optional number
attribute `AccentShade` like BaseService does: > 0 towards white, < 0 towards black) from
`ReplicatedStorage.Shared.Config.BaseConfig` (the ModuleScript source is executed in a
sandbox with `Color3`, `Vector3`, `Enum`, ... and a `require` that works for other
ModuleScripts in the place). If that module is missing or fails, a built-in 8-colour
palette is used; the JSON field `baseColorSource` says which one was used.
`--no-bases` turns the simulation off.

JSON layout:

```jsonc
{
  "parts": [{
    "name": "Pier", "path": "VirtualBase1:ServerStorage.BaseTemplate.Pier",
    "className": "Part", "shape": "Block",        // Block | Ball | Cylinder | Wedge | CornerWedge
    "cf": [x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22],
    "size": [sx, sy, sz], "color": [r, g, b], "transparency": 0, "material": "Wood",
    "kind": "base", "baseIndex": 1                // baseIndex only for kind "base"
  }],
  "slots": [{ "index": 1, "name": "Slot1", "cf": [...], "color": [r, g, b] }],
  "bounds": { "min": [...], "max": [...], "contentMin": [...], "contentMax": [...] },
  "stats": { "part": 0, "water": 0, "base": 0, "bases": 0, "skippedInvisible": 0 },
  "baseColorSource": "BaseConfig"
}
```

`cf` is the CFrame: position, then the rotation matrix row-major (`world = R * local + p`,
the look vector is the negated third column). `contentMin/contentMax` ignore parts wider
than 1000 studs (the default `Baseplate`). MeshParts, unions and trusses are exported as
`Block` (their bounding box).

## render.py

```
python3 tools/preview/render.py <parts.json> --out-dir <dir> [options]
```

| option | default | meaning |
|---|---|---|
| `--views LIST` | `top,iso,iso2,zoom` | which images to render: any of `top,iso,iso2,zoom,persp`. With `--persp`/`--persp-preset` and no `--views`, only `persp`. |
| `--zoom X,Z,R[,AZ]` | first base slot, radius 40 | zoom target; repeat for `zoom_1.png`, `zoom_2.png`, ... Optional 4th value = azimuth (default 45). Negative values work (`--zoom -57,-57,30`). |
| `--size PX` | 1600 | output width in pixels (height follows the scene, zoom is 4:3, persp is 16:9) |
| `--ss N` | 2 | supersampling factor (anti-aliasing) |
| `--elevation DEG` | 35 | camera elevation of the 3D views |
| `--frame auto\|all` | `auto` | `auto` frames the play area: ignores Baseplate-sized parts, water and the outermost 1% of part extents (e.g. ocean-floor slabs), but always includes every base. `all` frames everything except Baseplate-sized parts. |
| `--bounds XMIN,ZMIN,XMAX,ZMAX` | | frame this XZ rectangle instead |
| `--zoom-cull F` | 2.0 | zoom views hide parts farther than `radius * F` from the centre so they don't block the view (0 = off) |
| `--no-outlines` | | no dark edge lines |
| `--no-labels` | | no base-slot number markers |
| `--terrain FILE` | | also draw smooth terrain: heightfield `.npz`/`.json` from `terrain_export.py`, or a raw SmoothGrid `.bin` (decoded on the fly). See [Terrain](#terrain). |
| `--terrain-step STUDS` | auto | terrain quad size: 4 = native voxel columns, 8/16/... = averaged. Auto picks the smallest of 4, 8, 16, ... studs whose quads cover >= 5 output pixels (full 1400-stud world at 1600 px: 8; zooms: 4; persp: per distance ring, see below). |
| `--persp EX,EY,EZ,TX,TY,TZ[,FOV]` | | perspective view from eye `(EX,EY,EZ)` looking at `(TX,TY,TZ)` (studs), vertical field of view `FOV` degrees (default 70, the Roblox default). Repeat for `persp_1.png`, `persp_2.png`, ... Negative values work (`--persp -60,30,-60,0,10,0`). |
| `--persp-preset ring` | | 6 automatic views of the ring map (see below), numbered after any `--persp` views. `--views persp` without `--persp` also uses it. |
| `--fog START,END` | `300,1500` | persp distance fog: starts at `START` studs, 90 % fogged at `END` |
| `--no-fog` | | persp: no fog |

`parts_json` may be `-` (no parts) to render terrain alone.

Views:

* **top**: orthographic, looking down -Y. **+X is to the right, +Z is down.** Grid lines
  every 16 studs (faint) and 32 studs (stronger), the X=0 / Z=0 axes in red / blue,
  coordinate labels on the top and left edges.
* **iso**: camera at azimuth 45 deg (in the +X/+Z quadrant, looking towards -X/-Z),
  elevation 35 deg. On screen +X points right-down, +Z left-down (see the gizmo).
* **iso2**: azimuth 225 deg, the opposite side (camera in the -X/-Z quadrant).
* **zoom**: iso-style view centred on (X, Z), `R` studs from the centre to the left/right
  edge. Azimuth is measured from +Z towards +X (0 = camera on the +Z side, 90 = +X side).
* **persp**: perspective view from a given eye point, roughly what a player sees; see
  [Perspective views](#perspective-player-eye-views).

Base slots are marked with a numbered circle in the base colour (at the slot position).

Geometry rules (Roblox conventions): blocks; `Cylinder` along local X, diameter
`min(size.Y, size.Z)`, drawn as a 16-gon prism; `Ball` diameter `min(size)`, low-poly
sphere; `Wedge` has a full bottom and full back (+Z) face, slope facing -Z/+Y;
`CornerWedge` has a rectangular base and the apex above the (+X, -Z) corner.

Shading: flat, ambient + half-Lambert from a fixed sun; `Neon` is unshaded and brighter.
Water is drawn as semi-transparent blue whatever its colour/transparency; other parts
use `1 - Transparency` as opacity. Only the nearest transparent surface per pixel is
blended (adjacent water volumes merge without seams; glass in front of water hides the
water behind it). Coplanar faces z-fight like in Roblox, except that Baseplate-sized
parts lose ties to everything else.

Performance: ~2500 parts render in about 0.5-1.5 s per view (4 views in ~4 s) at the
default size.

## Perspective (player-eye) views

```sh
OUT=/tmp/preview
$LUNE run tools/preview/export_parts.luau   Place1.rbxl $OUT/parts.json
$LUNE run tools/preview/export_terrain.luau Place1.rbxl $OUT/smoothgrid.bin   # water
# 6 automatic views of the ring map -> persp_1.png .. persp_6.png
python3 tools/preview/render.py $OUT/parts.json --terrain $OUT/smoothgrid.bin --out-dir $OUT \
    --persp-preset ring
# your own: eye (0, 12, 12) looking at (0, 8, 312), and a 50-degree view from above slot 2
python3 tools/preview/render.py $OUT/parts.json --terrain $OUT/smoothgrid.bin --out-dir $OUT \
    --persp 0,12,12,0,8,312 --persp 330,60,140,250,4,100,50
# together with the orthographic views
python3 tools/preview/render.py $OUT/parts.json --terrain $OUT/smoothgrid.bin --out-dir $OUT \
    --views top,iso,persp --persp-preset ring
```

The camera is a pinhole camera without roll (the image's horizontal axis stays
horizontal); the vertical field of view is `FOV`, images are 16:9 (`--size` x
`--size * 9/16`, default 1600 x 900). The info box gives eye, target, heading (0 = +Z,
90 = +X), pitch, FOV, fog and how many faces are in view.

What it draws:

* Same geometry, lighting, outlines and transparency rules as the orthographic views.
  Depth is a z-buffer of `-1/distance`. Faces entirely outside the view frustum are culled
  first. The rest are clipped against the near plane (0.3 studs) and a guard band, so
  parts beside or behind the camera, or around it (the floor under the eye, a
  long water strip), are cut cleanly. A camera inside a part sees through it (back faces
  are culled).
* Background: sky gradient by view elevation, light blue at the horizon to deeper blue at
  the zenith (below the horizon, the horizon colour).
* Distance fog (Roblox `Atmosphere`-like): surface colours blend into the sky colour behind
  them, `1 - exp(-2.3 * ((d - START) / (END - START))^1.5)`: 0 up to 300 studs, ~25 % at
  600, ~63 % at 1000, 90 % at 1500 (defaults). Very high cameras (y > ~1500) see only fog;
  use `--no-fog` or e.g. `--fog 2000,6000` there.
* Outlines are full strength up to 60 studs, fade out by 400 studs and are not drawn
  beyond.
* Water (water parts and `--terrain` water) is translucent from above and turns opaque
  and sky-tinted at grazing angles (Fresnel), so open water reads correctly towards
  the horizon. Terrain water covers its whole area, out to the horizon. Beyond the
  terrain's edge there is only sky; fog hides the edge at distance. Water is one-sided:
  a camera under the water surface sees no surface.
* Terrain uses rings of detail around the eye: 4-stud quads where they span >= 5 px, then
  8, 16, ... studs further out (about 500 / 1000 / 2000 studs at 1600 x 900, FOV 70).
  Each ring's edge follows the next coarser ring's surface, so they meet without cracks.
  `--terrain-step` forces one size everywhere.
* Base slots get their numbered marker (faint when hidden behind something, none beyond
  the fog). `--no-labels` turns them off.

### `--persp-preset ring`

Six views of the ring map, assuming the lagoon centre is the origin. Ring radius and
directions come from the JSON `slots` (slot 1 first). Bridges are found as parts whose
path contains "bridge" (e.g. `Workspace.Map.Bridges.Bridge_1`). Eye heights are put on
the surface found under the eye (parts or terrain), and eyes are moved so they are not
inside a part.

| # | view | eye | looks at |
|---|---|---|---|
| 1 | hub centre | just outside the hub centre (>= 12 studs) on the bridge axis nearest slot 1, ground + 8 (y ~ 12) | the ring along that axis, y 8 |
| 2 | bridge | 3/4 along the next bridge round (+90 deg), deck + 7 | the hub (0, 14, 0) |
| 3 | plot front | slot 1's plot, a few studs inside its front edge (slot-local -Z, the lagoon side), ground + 6 | the lagoon / hub (0, 6, 0) |
| 4 | above a base | 26 studs behind the back edge of the plot opposite slot 1, y = 60 | the middle of that plot |
| 5 | ocean | open water (no part within 220 studs) at the 90th-percentile island radius + 350 studs (inside the terrain), first clear direction from slot 1's, y = 40 | the island (0, 12, 0) |
| 6 | overview | 2 x ring radius out, 45 deg from view 1's axis, y = 350 | the origin |

Without slots, views 3 and 4 are skipped and a 300-stud ring is assumed. The chosen
positions are printed (`[render] persp_N: eye (...) -> target (...)`), so a view can be
re-rendered or adjusted with `--persp`.

Speed: the current place (11.3k parts, 120k faces, 2800 x 2800-stud terrain water)
takes 2.5-3.5 s per 1600 x 900 view (`--ss 2`), the 6-view preset ~18 s. A 21k-part
copy (219k faces) takes 3-5.5 s per view.

## Checking orientation quickly

Render a place and confirm in `top.png` that a part at +X is on the right and a part
at +Z is below the centre; the iso gizmo shows the projected +X/+Y/+Z axes.

## Prop gallery (gallery.luau)

`gallery.luau` builds a showcase place with every constructor of
`tools/builder/Props.luau` (several seeds/variants of the trees) on a checkered green
ground, with a water channel (a `Workspace.Map.Water` stand-in) for the boats, docks,
shipwreck, whale, rock arch, bridges and a waterfall off a cliff, a row of landmarks and
balloons/clouds in the sky. It fails if a public `Props` function is not shown, prints the
parts per prop and a `--zoom` target per section:

```sh
$LUNE run tools/preview/gallery.luau /tmp/gallery.rbxl
$LUNE run tools/preview/export_parts.luau /tmp/gallery.rbxl /tmp/gallery.json --no-bases
python3 tools/preview/render.py /tmp/gallery.json --out-dir /tmp/gallery --no-labels \
    --views iso,zoom --elevation 28 --zoom 140,20,100,25 --zoom 75,140,62,22
```

Props face +Z (towards the default iso camera). Renders of the current library are in
`docs/props/`.


## Terrain

The place's smooth terrain lives in two binary properties of `Workspace.Terrain`:
`SmoothGrid` (the voxels) and `PhysicsGrid` (collision regions derived from them). Three
tools read them; none needs Roblox Studio.

| tool | what |
|---|---|
| `tools/preview/export_terrain.luau` | Lune: writes the raw `SmoothGrid` (and optionally `PhysicsGrid`) bytes of a place to files |
| `tools/preview/terrain_export.py` | Python + numpy: decodes `SmoothGrid` bytes into a heightfield (`.npz`/`.json`) for `render.py --terrain`; `--stats`/`--sample` for inspection |
| `tools/terrain_check/` | Rust CLI with the vendored reference codec (`rbx_terrain` from github.com/chteau/rbx-native, MIT, verified upstream against a real place byte for byte): decodes, prints statistics, checks the bytes are canonical and that `PhysicsGrid` matches, samples voxels |

### Rendering terrain

```sh
LUNE=/opt/tools/l11/lune
OUT=/tmp/preview
$LUNE run tools/preview/export_parts.luau   Place1.rbxl $OUT/parts.json
$LUNE run tools/preview/export_terrain.luau Place1.rbxl $OUT/smoothgrid.bin $OUT/physicsgrid.bin
python3 tools/preview/terrain_export.py $OUT/smoothgrid.bin --out $OUT/terrain.npz --stats
python3 tools/preview/render.py $OUT/parts.json --terrain $OUT/terrain.npz --out-dir $OUT \
    --zoom 0,0,120 --zoom 380,0,200,30
# terrain only (no parts):  python3 tools/preview/render.py - --terrain $OUT/terrain.npz --out-dir $OUT
```

(`--terrain $OUT/smoothgrid.bin` also works and skips the `.npz` step; decoding a
1400 x 1400-stud world takes ~0.3 s.)

How terrain is drawn:

* Heightfield on the 4 x 4-stud voxel column grid. Column surface = bottom of the highest
  solid (non-Air, non-Water) voxel + 4 studs x its fill fraction `(occupancy + 1) / 256`.
  Overhangs and caves are not shown (only the top surface).
* Every grid corner takes the mean height of the up to four columns around it; a column
  is two triangles (flat runs of columns are merged into quads). One-column ridges and
  channels get a 4-triangle fan through the column centre at its exact height.
  Vertical walls close the terrain where it ends.
* Colour = the top voxel's material (table `TERRAIN_COLORS` in `render.py`) with a
  +-4 % per-column brightness variation; same lighting as parts. Material borders follow
  the column grid, so they look stair-stepped (and saw-toothed in the 45-degree views).
* Water: a translucent sheet (same colour/opacity as water parts) at the water surface of
  columns whose water lies above the solid surface, with translucent walls at open edges.
* Terrain and parts share the depth buffer. Zoom views crop the terrain to the same square
  as `--zoom-cull`; the zoom's vertical centre also uses the terrain surface.
* Speed: a 1408 x 1408-stud world (124k columns) renders top/iso/iso2 + 2 zooms in
  ~9 s at the default size (iso at 8-stud quads ~1.4 s, 4-stud zooms ~1.5-2.5 s).

### Heightfield file (`terrain_export.py --out`)

Arrays are indexed `[iz, ix]`; column `(ix, iz)` covers studs
`x = origin[0] + 4*ix .. +4`, `z = origin[1] + 4*iz .. +4` (empty margins trimmed).

| key | type | meaning |
|---|---|---|
| `origin` | 2 floats | stud x, z of column (0, 0)'s min corner |
| `step` | float | 4 (studs per column) |
| `top` | float32 | solid surface y; NaN = no solid voxel in the column |
| `material` | int16 | material slot of the top solid voxel (index into `materials`); -1 = none |
| `bottom` | float32 | bottom y of the lowest solid voxel |
| `water` | float32 | water surface y if water lies above the solid surface (or the column has no solid), else NaN; includes the liquid share of a partly filled top voxel |
| `materials` | 23 strings | slot names: Air, Water, Grass, Slate, Concrete, Brick, Sand, WoodPlanks, Rock, Glacier, Snow, Sandstone, Mud, Basalt, Ground, CrackedLava, Asphalt, Cobblestone, Ice, LeafyGrass, Salt, Limestone, Pavement |

`.json` holds the same keys (NaN as `null`, rows as nested lists) plus `size: [nx, nz]`.

### terrain_check (validating SmoothGrid / PhysicsGrid)

Build once (crates.io is needed for the first build only; `Cargo.lock` is committed, later
builds work with `--offline`):

```sh
cargo build --release --manifest-path tools/terrain_check/Cargo.toml
TC=tools/terrain_check/target/release/terrain_check
```

```sh
$TC Place1.rbxl                                   # full check of the place's Terrain
$TC --raw smoothgrid.bin physicsgrid.bin          # same, for raw blobs
$TC --raw smoothgrid.bin                          # PhysicsGrid check skipped
$TC --sample Place1.rbxl 120 6 -40                # voxel at stud (x, y, z) + its column
$TC -q Place1.rbxl                                # only the check lines
$TC Place1.rbxl --dump DIR                        # also write the place's blobs to DIR
$TC --raw sg.bin --emit DIR                       # write the reference encoding of the voxels
```

Output: chunk count and range, voxel counts (solid / water / with liquid share), voxel
bounding box in studs, voxels per material (full + partial), occupancy histogram,
solid/water surface height range over the 4 x 4 columns, a SHA-256 digest of the decoded
voxels, then

* `canonical:` the reference encoder re-encodes the decoded voxels and the bytes must be
  identical. On a mismatch it prints the first differing byte and the chunk it belongs to,
  hex of both streams there, how many chunks differ, and which non-canonical patterns the
  input uses (runs split although they could continue up to 256, explicit occupancy byte
  255, Air with an occupancy byte, liquid byte on a voxel that cannot hold one, count-0
  record with liquid 0, unsorted chunks, stored all-Air chunks).
* `PhysicsGrid:` recomputed from the voxels with the reference encoder (version 2, 8^3-voxel
  regions grown by one voxel, all in the first of three lists) and compared byte for byte;
  a mismatch lists region counts and examples of extra/missing regions.

Exit status: 0 = all OK, 1 = a check failed (non-canonical, PhysicsGrid mismatch or
missing in a place), 2 = usage/I-O/decode error (the decode error names the chunk and byte).

Rules the reference encoder follows (what "canonical" means): header `01 05`; chunks of
32^3 voxels sorted by x, then y, then z, each with its key offset from the previous one as
three big-endian i32 with interleaved bytes; voxels x fastest, then z, then y; greedy runs
of up to 256 identical voxels; occupancy byte only when it is not the default (Air 0,
anything else 255); a partly filled solid voxel with a liquid share is a one-voxel record
`lead|0x80, 0, liquid`; all-Air chunks are omitted.

### Cross-checking the two decoders

`terrain_export.py --stats` prints the same summary lines as `terrain_check`, from an
independent decoder:

```sh
$TC --raw $OUT/smoothgrid.bin | sed -n '2,/digest/p' > /tmp/rs.txt
python3 tools/preview/terrain_export.py $OUT/smoothgrid.bin --stats 2>/dev/null > /tmp/py.txt
diff /tmp/rs.txt /tmp/py.txt && echo identical
python3 tools/preview/terrain_export.py $OUT/smoothgrid.bin --sample 120 6 -40   # vs $TC --sample
```

### Test terrain without a generator

`terrain_demo` (built with `terrain_check`) writes blobs with the reference encoder;
`tools/terrain_check/inject.luau` puts blobs into a copy of a place:

```sh
D=tools/terrain_check/target/release/terrain_demo
$D /tmp/tt              # 320 x 320 studs: grass hill with rock/slate cliff ring and snow cap,
                        # sand-rimmed pool (water to y=12), cobblestone road, pavement square
$D /tmp/tt --big        # 1408 x 1408-stud lake/mountain world (renderer timing)
$D /tmp/tt --random     # 4000 random voxels, every material/occupancy/liquid (decoder tests)
$LUNE run tools/terrain_check/inject.luau tools/base/Place1.base.rbxl \
    /tmp/tt/smoothgrid.bin /tmp/tt/physicsgrid.bin /tmp/tt/place.rbxl
$TC /tmp/tt/place.rbxl
```

## GUI previews

See the HUD exactly as a player would — on a phone, a tablet or a PC — without Roblox Studio:
still images of every HUD state and contact sheets of the animations, drawn over a real frame
of the game (the pier view) with the Roblox CoreGui chrome on top. Made for design critique:
everything is a PNG.

```sh
# the standard set: 33 states x phone + desktop, 14 animation sheets each, 2 overviews (~1.5 min)
python3 tools/preview/gui_render.py --all --out /tmp/ui
# a few scenarios (dumped first), with their animation sheets, on three devices
python3 tools/preview/gui_render.py --scenario bite,catch_mythic --devices phone,tablet,desktop --sheets --out /tmp/ui
# other moments: stills at 0.1 and 0.4 s, or a custom sheet window (from:to:fps)
python3 tools/preview/gui_render.py --scenario hit --at 0.1,0.4 --out /tmp/ui
python3 tools/preview/gui_render.py --scenario catch_rare --times 0:3:5 --out /tmp/ui
# re-render existing dumps (e.g. after changing the renderer) — no Lune needed
python3 tools/preview/gui_render.py /tmp/ui/json/phone/*.json --out /tmp/ui
python3 tools/preview/gui_render.py --list          # scenario names and descriptions
```

Needs Python 3 with Pillow (with raqm) and numpy, and Lune 0.11 (`LUNE_BIN`, default
`/opt/tools/l11/lune`) for dumping. Build the place first (`lune run tools/build.luau`); to
preview another checkout's HUD, build it there and pass `--place /path/to/its/Place1.rbxl`
(the scenarios and the renderer come from this checkout, the HUD and its controllers from the
place).

Output in `--out`:

| file | what |
|---|---|
| `<device>/<scenario>.png` | the still: the whole screen + a caption bar (device, scenario, time). Several still times: `<scenario>@<t>.png` |
| `<device>/<scenario>_sheet.png` | animation contact sheet: every frame of the scenario's sheet window cropped to its region of interest, each labelled with its time |
| `overview_<device>.png` | every still of the device in one image (with `--all`, or more than 3 dumps) |
| `json/<device>/<scenario>.json` | the dumps (see below) |

Examples of the current HUD are in `docs/ui/`.

### How it works

1. `tools/preview/gui_dump.luau` (Lune) loads `Place1.rbxl` into RbxSim, replaces the source of
   `ServerScriptService.Services.FishingService` with `return {}` (like
   `tests/stage2_client.test.luau`), starts the server and, for each scenario, adds a fresh
   player on the device (phone 844x390, tablet 1024x768, desktop 1280x720; touch on phone and
   tablet), waits for the base, the character and the HUD plus `settle` seconds (4.2 s: the
   welcome toast is gone), runs the scenario — the REAL client controllers react to what the
   harness (playing the server) sends — and dumps the player's PlayerGui at the requested
   times (60 fps virtual time in between). Script errors and warnings of the run go into the
   dump and are printed.
2. `tools/preview/gui_render.py` draws each dump at the device resolution, 2x supersampled:
   the backdrop, every GuiObject in draw order (`gui/paint.py`, text in `gui/text.py`), then
   the CoreGui chrome (`gui/backdrop.py`), and downsamples.
   `--all` runs the dumps in parallel Lune processes (`--jobs`, default = CPU count, max 8,
   split across devices) and renders in a process pool.

Speed (4 cores): the standard set takes ~45 s to dump and ~35 s to render (66 stills,
28 sheets); one scenario on one device ~2 s to dump, a still ~0.2-0.3 s.

### Scenarios (`tools/preview/gui_scenarios.luau`)

| scenario | state | sheet |
|---|---|---|
| `spawn_base` | the badge right when the server assigns the base (welcome toast) | 0..1.2 s, status |
| `no_base` | all bases taken: «Ждём базу…» | |
| `start` | just spawned, rod in the backpack, newcomer hint | |
| `rod_far` | rod in hand, far from the fishing spot (hint) | |
| `spot_take` | at the spot, rod in the backpack: «ВЗЯТЬ» | |
| `spot_ready` | at the spot with the rod: «ЗАБРОСИТЬ» | 0..4 s @ 6 fps (idle shine) |
| `cast` | tap «ЗАБРОСИТЬ» → waiting | 0..1 s, action area |
| `waiting` | line in the water: «ЖДЁМ…» + «СМОТАТЬ» | |
| `bite` | «КЛЮЁТ!» alert + «ПОДСЕЧЬ!» | 0..1.2 s |
| `minigame_common` … `minigame_mythic` | the minigame for each rarity, needle mid-run (Epic 1/2, Mythic 2/3 hits done) | legendary: 0..1 s |
| `hit` | a hit: zone jumps, pip fills | 0..0.9 s |
| `miss` | a miss: «Мимо!» | 0..1.2 s |
| `lost_late`, `denied_far` | hints of a lost fish / a refused cast | |
| `catch_common`, `_rare`, `_epic`, `_legendary`, `_mythic` | catch card per rarity (time 0 = the card is visible) | common 0..1.6 s, mythic 0..2.4 s (whole screen) |
| `catch_gold`, `catch_neon`, `catch_rainbow` | catch card with a mutation | rainbow 0..1.6 s |
| `catch_close` | tap closes the card, the counter bumps | 0..1 s, whole screen |
| `toast_info`, `toast_success`, `toast_warning`, `toast_danger` | one toast of each kind | success 0..0.8 s |
| `toast_stack` | three toasts (the cap), then the oldest leaves | 3..4.4 s |
| `home_cooldown` | «ДОМОЙ» pressed, cooldown draining | 0..0.8 s |
| `selftest` (not in `--all`) | a synthetic ScreenGui, one cell per renderer feature — check the renderer here | |

Scenarios find widgets by name only (`HUD.Fishing.ActionArea.ActionButton`, `HUD.Fishing.CatchCard`,
`HUD.RightButtons.HomeButton`, ...), so they survive restyles; a missing or hidden widget is a
warning, not a crash (clicks are forced). A scenario is
`{ name, desc, run = function(h) ... end, still = t | {t...}, sheet = { from, to, fps, roi = {paths}, margin }, fresh?, settle?, standard? }`;
time 0 is when `run` returns. The harness `h` is documented in the file's header:
`h:advance`, `h:gui`, `h:visible`, `h:waitFor`, `h:waitVisible`, `h:click`, `h:press`,
`h:serverSays(state, data)` (FishingState), `h:notify(text, kind)`, `h:giveRod`, `h:equipRod`,
`h:standAtSpot`, `h:standFar`, `h:config`, `h:minigame(rarity, extra)`, `h:caught(fish, total)`.
The sheet region is the union of the `roi` objects' screen boxes over all sheet frames plus
`margin` x screen height (none listed or none visible = the whole screen).

### gui_dump.luau

```
lune run tools/preview/gui_dump.luau --device phone|tablet|desktop|console --scenario a,b|all --out DIR
    [--place Place1.rbxl] [--at T,T] [--sheets] [--times A:B:FPS] [--no-stills] [--check] [--verbose]
lune run tools/preview/gui_dump.luau --list
```

`--check` compares the dump's layout with RbxSim's `AbsolutePosition/AbsoluteSize` and prints
the differences (expected only where RbxSim is approximate: list alignment, UIScale, rotation).

The dumper lays the GUI out itself (RbxSim ignores UIScale, rotation and list alignment):
UDim2 Size/Position, AnchorPoint, SizeConstraint, UISizeConstraint, UIAspectRatioConstraint
(FitWithinMaxSize / ScaleWithParentSize + DominantAxis), UIPadding, UIListLayout (direction,
both alignments, padding, LayoutOrder/Name sort), UIGridLayout (cell size/padding, alignment,
FillDirectionMaxCells), ScrollingFrame canvas, ScreenGui insets (`IgnoreGuiInset` / `ScreenInsets`
None and DeviceSafeInsets = full screen, CoreUISafeInsets = below the 58 px top bar).
Then:

* **UIScale** scales the object and its whole subtree visually about the object's AnchorPoint —
  offsets, corner radii, stroke thickness and text sizes included; nested scales multiply.
* **Rotation** turns the object and its subtree about the object's (scaled) centre; rotations
  accumulate.
* **Clipping**: ClipsDescendants, CanvasGroup and ScrollingFrame clip descendants to the
  object's screen rectangle — ignored when the object or an ancestor is rotated (Roblox rule).
  CanvasGroup's GroupTransparency multiplies the opacity of its subtree.
* **Draw order**: ScreenGuis by DisplayOrder; `ZIndexBehavior.Sibling`: a parent before its
  children, siblings by ZIndex then child order; `Global`: everything by ZIndex then tree order.

One JSON per device and scenario: `{ version, scenario, desc, device, viewport, touch, inset,
sheet, frames = [{ t, still, sheet, tools = [{name, equipped}], objects = [...] }], errors,
warnings }`. Objects are the effectively visible GuiObjects in draw order, in screen pixels:
`path, class, name, z, x, y, w, h` (the box before rotation; rotate about its centre),
`rot, k` (accumulated rotation and UIScale), `clip, alpha, bg, bgT, radius / radii`
(UICorner in px), `border` (legacy, only without UICorner and a Border UIStroke),
`strokes` (`color, t, offset, tr, target border|text, pos Outer|Center|Inner, join, grad`),
`grad` (UIGradient: `c` colour keypoints, `a` transparency keypoints, `rot, off, type, tile,
scale`), `text` (`s, rich, c, tr, sc, st, scaled, size, wrap, xa, ya, font, weight, style, lh,
min, max, pad, trunc, graphemes`), `image`, `viewport` (`models` = name, fish id, mutation,
title, rarity), `auto` (AutomaticSize — flagged, not applied). The full field list is in the
script's header.

Lune notes: Lune 0.11's reflection database stores `UICorner` as four per-corner radii
(`TopLeftRadius`...; `CornerRadius` cannot be read back from a saved place, while one set at
runtime can), knows `UIGradient.Type/TileMode/Scale` and
`UIStroke.BorderStrokePosition/StrokeSizingMode/BorderOffset` — all read by the dumper. New
GuiObjects have `BorderSizePixel = 1`, so a visible background without UICorner/UIStroke gets
Roblox's 1 px dark border, as in the game.

### gui_render.py

| option | default | meaning |
|---|---|---|
| `DUMP.json ...` | | render these dumps (no dumping) |
| `--all` | | the standard set (every scenario but `selftest`), stills + sheets, overviews |
| `--scenario LIST` | | dump and render these scenarios |
| `--devices LIST` | `phone,desktop` | `phone`, `tablet`, `desktop`, `console` |
| `--sheets` | off (on with `--all`) | also the animation sheets |
| `--at T,T` / `--times A:B:FPS` | | still times / sheet window for every scenario |
| `--out DIR` | | output directory (required) |
| `--bg MODE` | `pier` | `pier` (rendered game frame), `plain` (sky/sea gradient), or an image path (cover-fitted) |
| `--no-chrome` | | no Roblox CoreGui overlay |
| `--no-caption` | | no caption bar under the stills |
| `--no-overview` | | no overview images |
| `--ss N` | 2 | supersampling |
| `--place FILE` | `Place1.rbxl` | the place to dump (and to render the backdrop from) |
| `--jobs N` | CPU count (max 8) | parallel Lune dumps / render workers |
| `--list`, `-v` | | list scenarios / print every dump log line |

**Backdrop** (`--bg pier`): `render.py`'s perspective renderer at the device resolution — the
Roblox default third-person camera (12.5 studs behind the head, 18 deg down, vertical FOV 70)
behind a blocky stand-in avatar (classic R6 colours, bamboo rod raised) on base 1's
FishingSpot, looking over the lagoon. Parts/terrain come from `export_parts.luau` /
`export_terrain.luau`; the image is cached in `tools/preview/gui/.cache/` (git-ignored; key =
place path, size, mtime + resolution; `GUI_PREVIEW_CACHE` moves it), ~3 s per new resolution.
If it cannot be rendered, `docs/preview_pier.png` is cropped instead.

**CoreGui chrome** (drawn over the HUD at 80 % opacity, so overlaps stay visible): the 58 px
top bar (Roblox menu button, chat/more pill); on desktop the open chat window (top-left,
360x180) and the player list (top-right); the hotbar — 60 px slots centred, 5..65 px above the
bottom, one per tool from the dump (number, wrapped name, white frame on the equipped one);
on touch devices the classic thumbstick and the Jump button: short side <= 500 px: 70 px at
25..95 px from the right and 20..90 px from the bottom (thumbstick mirrored on the left);
bigger screens: 120 px at (W-170..W-50, H-210..H-90) (thumbstick at x 60..180).

**Painting** (Roblox rules as implemented; the `selftest` scenario shows each one):

* Shapes are signed-distance anti-aliased at 2x: UICorner radius = scale x the shorter side +
  offset, clamped to half the shorter side, per corner.
* UIStroke on a border (`Border`, or `Contextual` on a non-text object): a ring OUTSIDE the box
  by default (outer corners rounded r + thickness — round joins), Center/Inner per
  `BorderStrokePosition`, shifted by `BorderOffset`, thickness x the shorter side with
  `StrokeSizingMode.ScaledSize`; coloured by its own UIGradient across the object's box;
  independent of BackgroundTransparency.
* UIGradient on the object multiplies BackgroundColor3 and TextColor3 (not emoji) and the
  opacity. Linear: `t = 0.5 + ((u-0.5-Offset.X) cos R + (v-0.5-Offset.Y) sin R) / Scale` over the
  normalised box (Rotation 90 = top to bottom); Elliptical: 2 x the normalised distance from the
  centre; Radial: a circle fitted to the shorter side; Conical: the angle from Rotation,
  clockwise; TileMode Clamp/Repeat/Mirror.
* Text: TextSize is the line height (Nunito's ascent + descent are scaled to it, so the em is
  TextSize / 1.364); TextScaled picks the largest whole size <= MaxTextSize (100 without a
  UITextSizeConstraint) and >= MinTextSize whose text, wrapped at spaces, fits the box without
  splitting a word; if none fits, the min size is used, long words are split and the text may
  overflow (that is what MinTextSize 9 on «ДОМОЙ» avoids). Alignment X/Y, LineHeight,
  TextWrapped, TextTruncate AtEnd, MaxVisibleGraphemes (typewriter: the full layout, first N
  graphemes drawn), RichText tags stripped, UIPadding on the label.
* Font: Nunito (variable, `FontFace.Weight` 200-1000) from `tools/preview/fonts/Nunito.ttf`
  (SIL OFL 1.1, `fonts/OFL.txt`) for every family (others warn once); characters Nunito lacks
  (→, ★) use DejaVu Sans Bold. Colour emoji from Noto Color Emoji (`GUI_PREVIEW_EMOJI_FONT`
  overrides the path), drawn at the text's em size (1.17 em tall, 1.25 em advance), mixed with
  text in the same line.
* Text outlines: a UIStroke on a text object (`Contextual`) outlines glyphs and emoji with its
  thickness, under the fill; the legacy TextStroke is a thin outline of max(1, 0.045 x TextSize)
  px; both fade with TextTransparency.
* ViewportFrame: the fish sprite `docs/gear/<Fish>_iso.png` (`_Gold/_Neon/_Rainbow.png` for a
  mutation) with the render's light background and Neon glow keyed out (a ViewportFrame has no
  bloom), fitted (6 % margin) and centred, tinted by ImageColor3/ImageTransparency. The fish is
  found by the model's `Title` attribute in `ReplicatedStorage.Assets.Fish`.
* ImageLabel/ImageButton: images cannot be fetched (rbxasset/rbxassetid) — a soft glow tinted
  with ImageColor3 stands in.

**Known limits**: no AutomaticSize (flagged in the dump, printed by the renderer), UIFlexItem /
flex layouts, UIPageLayout/UITableLayout, rich-text styling, TextBox placeholders, device
safe-area insets (notches), rounded clipping of CanvasGroups, or particles/3D world effects
(only the GUI). Roblox's exact font metrics and legacy TextStroke width are approximations;
TextScaled sizes may differ from Roblox by a pixel or two. Treat the renders as faithful for
layout, colour and composition, approximate for text rasterisation.

