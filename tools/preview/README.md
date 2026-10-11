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

