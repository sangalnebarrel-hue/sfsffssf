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
    "surfaces": { "Top": "Studs", "Bottom": "Inlet" }, // only Plastic parts, only non-Smooth faces
    "kind": "base", "baseIndex": 1                // baseIndex only for kind "base"
  }],
  "slots": [{ "index": 1, "name": "Slot1", "cf": [...], "color": [r, g, b] }],
  "bounds": { "min": [...], "max": [...], "contentMin": [...], "contentMax": [...] },
  "stats": { "part": 0, "water": 0, "base": 0, "bases": 0, "skippedInvisible": 0 },
  "baseColorSource": "BaseConfig"
}
```

`surfaces` (faces Top/Bottom/Front/Back/Left/Right → SurfaceType name) is written only for
`Plastic` parts (not trusses), like the engine draws surfaces only on Plastic: a part that lost
its Material shows up without studs in the preview too.

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
| `--no-studs` | | do not draw stud / inlet surfaces |
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

Studs (LEGO, `tools/builder/Studs.luau`): block faces with `Studs` (or `Universal`) in
`surfaces` get one stud per 1 × 1-stud cell, `Inlet` faces one hole per cell, drawn per pixel as
an albedo multiplier like the engine's studs atlas: a round stud of radius 0.3 cells with a lit
rim towards a fixed light direction in face space, a darker rim and a contact shadow on the
other side; inlets are dark holes with the far wall lit. The cell grid starts at the face's
min corner (an assumption: fractional faces get cut studs at the far edges). Below ~4.5 output
pixels per cell the pattern fades to its average (like mipmapping), so far ground stays calm
and the mean brightness of a face does not change. Ortho and persp views both draw them;
`--no-studs` turns them off. Costs ~0.3–1 s per view.
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

## Micro-detail views and KPIs (views.py, flatness.py, density.py)

Three small tools of the v3 micro-detail work (DESIGN.md §2/§3/§6):

```sh
OUT=/tmp/detail
$LUNE run tools/preview/export_parts.luau   Place1.rbxl $OUT/parts.json
$LUNE run tools/preview/export_terrain.luau Place1.rbxl $OUT/smoothgrid.bin
# eye-level views of base 1 (the fishing spot's follow camera, the pier walk, the yard, the ring
# beach either side of the pier, the promenade, the hub): "name eye,target,fov" lines
ARGS=$(python3 tools/preview/views.py 1 spot_default pier_walk beach | awk '{print "--persp " $2}')
python3 tools/preview/render.py $OUT/parts.json --terrain $OUT/smoothgrid.bin --out-dir $OUT $ARGS
# (views.py ... --parts $OUT/parts.json: an eye inside or within 1 stud of a part steps along its
# view direction until free and stands on the surface below — render.py's ring-preset rule; the
# presets are kept out of the current geometry, so it only prints a note when one needs a move)
# share of featureless 40-px tiles (whole frame / lower half): the "flat" look
python3 tools/preview/flatness.py $OUT/persp_*.png
# per zone: parts, small parts per 1 000 studs², empty 8x8-stud cells; --heatmap draws them
python3 tools/preview/density.py $OUT/parts.json --heatmap $OUT/heatmap.png
```

Per-base variants: `export_parts.luau` keeps a template instance with attributes `Variant = k`,
`VariantOf = n` only on the bases with `(Index - 1) % n + 1 == k`, like BaseService does, so a
render of base 2 shows base 2's pier scene (the GUI backdrop of gui_render.py is base 1's pier).

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

## Living world previews (ambient_dump.luau + ambient_sheet.py)

The client's living world (AmbientController and its helpers: wind and sway, bobbing boats with foam
rings, glints, jumping fish, schools, gulls, butterflies, dragonflies, clouds, chase lights, waterfall
flow) over time, as ONE client sees it. `ambient_dump.luau` runs the built place in RbxSim with a
player, puts the client's camera at named views, lets the real controllers run and dumps every
`--step` seconds the parts in view with the client-local CFrames / transparency (frame entries
replace the scene's by `id`). Particles, SurfaceGui rings and Beams get stand-ins (glints = small
bright balls, splash droplets, ring and foam outlines as segments, waterfall streaks sliding down
with the beam texture). It also prints the engine's numbers per view (parts moved + properties
written per frame, peak vs budget, items updated / culled, tier sizes, by kind).
`ambient_sheet.py` renders `<view>_sheet.png` (all frames), `<view>_motion.png` (the first frame
with everything that moved painted red, plus the engine's numbers), optionally `<view>_crop.png`
(one region of every frame, enlarged) and `<view>.gif`.

```sh
LUNE=/opt/tools/l11/lune
$LUNE run tools/build.luau
$LUNE run tools/preview/export_terrain.luau Place1.rbxl /tmp/amb/smoothgrid.bin
# views: spot (the fishing camera), spot_wide, pier, platform, hub, beach, waterfall, fair, garden, boat
$LUNE run tools/preview/ambient_dump.luau /tmp/amb/dump.json --views spot,platform,boat,garden \
    --frames 8 --step 0.25 [--jump spot] [--swoop spot] [--device phone|desktop]
python3 tools/preview/ambient_sheet.py /tmp/amb/dump.json /tmp/amb --terrain /tmp/amb/smoothgrid.bin \
    [--size 800] [--cols 4] [--crop spot:690,220,300,170 --zoom 2] [--gif]
```

`--jump VIEW` makes a fish jump right when that view's frames start (AmbientController.JumpSoon);
`--swoop VIEW` waits for the pier gull's low pass (AmbientController.SwoopSoon). ~20 s for 3 views
of 8 frames to dump, ~1 s per 800-px frame to render. Not shown: real particles (only the stand-ins),
the terrain water's waves, GlobalWind on smoke.

## Fisher animation previews (pose_dump.luau + pose_sheet.py)

The procedural fisher animation (FisherAnimController, FisherRig, FisherPoses, FisherRod) can be
reviewed without Studio. `pose_dump.luau` runs the built place in RbxSim with a rigged fisher
(`sim:AddPlayer{ rig = "R15" | "R6" }`, see tools/sim/README.md) and a watcher, and dumps what the
WATCHER's client sees (client-local joint poses, bent rod, bobber + line, leaping / held fish) as
parts JSON; `pose_sheet.py` draws every frame with render.py's perspective rasterizer twice: from
the default camera behind the fisher (12.5 studs, 18° down, FOV 70, + Humanoid.CameraOffset — the
GUI previews' camera) with the pier around, and from his right side on a plain deck.

```sh
LUNE=/opt/tools/l11/lune
$LUNE run tools/build.luau
# a real session: equip, cast (wind-up → release → throw), wait, bite, strike, reel, catch,
# trophy (landing squat + jump, a show-off), then a lost fish and a reel-in; 28 frames (the bite
# waits 4.5 s so a wait fidget shows)
$LUNE run tools/preview/pose_dump.luau /tmp/anim/timeline.json [--rig R6] [--joints AnimationConstraint] [--fish Crucian]
python3 tools/preview/pose_sheet.py /tmp/anim/timeline.json /tmp/anim/timeline.png [--only "wind,release,reel"] [--cols 5]
# every key pose of FisherPoses on its own (contact sheet of the pose data)
$LUNE run tools/preview/pose_dump.luau /tmp/anim/poses.json --mode poses [--rig R6]
python3 tools/preview/pose_sheet.py /tmp/anim/poses.json /tmp/anim/poses.png
```

Labels show the controller's phase and the rod bend at that moment. The sim avatar is a block
approximation of R15 (exact R6) without appearance; body parts are coloured by name (right arm
darker — it holds the rod). The sim stores whole-number attribute values as float32, so the
dumper keeps the casts off whole seconds (CastTime would round otherwise).

### Fishing world FX close-ups (fx_dump.luau)

`fx_dump.luau` records the OWN client of a rigged R15 fisher through a real session — cast,
landing, wait, nibble, bite, reel, the leap and the held trophy — with what FishingFxController
and its helpers draw: the line as its Bézier (sticks), trails as streaks of their last Lifetime,
every part in `Workspace.FishingFx` (the bobber, the fish shadow — pre-mixed with the water colour
under a thin water slab, because render.py blends only the nearest transparent surface —, drips),
the leaping / held fish. Each segment carries a close-up camera (`frame.close`: the rod tip from
the side for the cast, the bobber from above the pier for the wait, the fish from behind the
fisher for the trophy); `pose_sheet.py --views close` draws it (`game` = the default camera).

```sh
$LUNE run tools/build.luau
$LUNE run tools/preview/fx_dump.luau /tmp/fx/fx.json
# segments: cast land wait nibble bite reel leap trophy
python3 tools/preview/pose_sheet.py /tmp/fx/fx.json /tmp/fx/trophy.png --only trophy --views close --cols 8 --cell 280x200
python3 tools/preview/pose_sheet.py /tmp/fx/fx.json /tmp/fx/cast.png --only cast --views close,game --cols 6
```

render.py draws a `SpecialMesh` of type Sphere as an ellipsoid (`MESHES["Ellipsoid"]`); other
mesh shapes are still their box.

## GUI previews

See the HUD exactly as a player would — on a phone (also a notched one and a small one), a
tablet or a PC — without Roblox Studio: still images of every HUD state, contact sheets of the
animations, 30 fps bursts of the punchy first 0.8 s, and timelines where the 3D world plays
UNDER the HUD with a beat ruler under every frame: the real posed avatar (FisherAnimController:
wind-up, throw, bite, reel with the bent rod, both arms up with the fish, the lost slump), the
line from the bent tip, the bobber, the fish shadow, the leap, the trophy's flop, the pillar,
confetti, and the ambient life in view (jumping fish, schools, gulls, dragonflies, foam rings,
swaying flags, the turning windmill and Ferris wheel). Drawn over a real frame of the game (the
pier view) with the Roblox CoreGui chrome on top, plus automatic checks: layout safety (gaps to
Jump, the thumbstick, the hotbar and between widgets), GPU fill per frame and the 12 px text
floor. Made for design critique: everything is a PNG (and a text report).

```sh
# the standard set: 50 states x phone + desktop (stills, 27 animation sheets each, 13 bursts on
# the phone, 2 overviews) + the checks on phone_notch, phone_small and tablet (~10 min on 4 cores)
python3 tools/preview/gui_render.py --all --out /tmp/ui
# the timelines (real server, the 3D world under the HUD, beat rulers), phone, ~2.5 min: the catch
# timelines + a whole session with the avatar (fishing_timeline), the trophy after the card
# (trophy_hold), a lost fish (lost_fish) and the living world from the pier tip (ambient_pier)
python3 tools/preview/gui_render.py --timeline --out /tmp/ui
python3 tools/preview/gui_render.py --timeline --devices phone,phone_notch --gif --out /tmp/ui
# one of them; the world without the HUD of the same frames is <scenario>_world.png
python3 tools/preview/gui_render.py --scenario fishing_timeline --devices phone --out /tmp/ui
# a few scenarios (dumped first), with their animation sheets and bursts, on three devices
python3 tools/preview/gui_render.py --scenario bite,catch_mythic --devices phone,phone_notch,desktop \
    --sheets --bursts --out /tmp/ui
# other moments: stills at 0.1 and 0.4 s, or a custom sheet window (from:to:fps)
python3 tools/preview/gui_render.py --scenario hit --at 0.1,0.4 --out /tmp/ui
python3 tools/preview/gui_render.py --scenario catch_rare --times 0:3:5 --out /tmp/ui
# re-render existing dumps (e.g. after changing the renderer) — no Lune needed
python3 tools/preview/gui_render.py /tmp/ui/json/phone/*.json --out /tmp/ui
python3 tools/preview/gui_render.py --list          # scenario names and descriptions
python3 tools/preview/gui_render.py --selftest      # the renderer's geometry and checks
```

Needs Python 3 with Pillow (with raqm) and numpy, and Lune 0.11 (`LUNE_BIN`, default
`/opt/tools/l11/lune`) for dumping. Build the place first (`lune run tools/build.luau`); to
preview another checkout's HUD, build it there and pass `--place /path/to/its/Place1.rbxl`
(the scenarios and the renderer come from this checkout, the HUD and its controllers from the
place).

Output in `--out`:

| file | what |
|---|---|
| `<device>/<scenario>.png` | the still: the whole screen + a caption bar (device, scenario, time, fill). Several still times: `<scenario>@<t>.png` |
| `<device>/<scenario>_sheet.png` | animation contact sheet: every frame of the scenario's sheet window cropped to its region of interest, each labelled with its time and fill |
| `<device>/<scenario>_burst.png` | the first 0.8 s at 30 fps (slams, stamps, pops, the catch), with the beat ruler when the scenario has beats |
| `<device>/<scenario>_timeline.png` | timelines: every frame full screen (or the timeline's `roi`) with the 3D world, x-ray boxes and a beat ruler (see below) |
| `<device>/<scenario>_world.png` | scenarios with `worldView`: the timeline's frames once more WITHOUT the HUD and the chrome — the avatar and the world the widgets hide (cropped to its `roi`) |
| `<device>/<scenario>_motion.png` | a `worldView` with a still camera (`ambient_pier`): its first frame with every pixel that changed during the clip painted red, and the share of the frame that moved |
| `<device>/<scenario>_layout.png` | a still with its layout-safety findings drawn: the gap in px between the closest points (red < 8 px, amber < 16 px, pink = a glow ring inside Jump/thumbstick) |
| `<device>/<scenario>_burst.gif`, `_timeline.gif`, `_world.gif` | with `--gif`: the same frames as an animation (real speed) |
| `overview_<device>.png` | every still of the device in one image (with `--all`, or more than 3 dumps) |
| `checks.txt`, `checks.json` | the checks of every dump: fill per frame (peak, median), layout findings and small text per still, the beats (see [Checks](#checks-fill-layout-safety-text-floor)) |
| `json/<device>/<scenario>.json` | the dumps (see below) |

Examples of the current HUD are in `docs/ui/`.

### How it works

1. `tools/preview/gui_dump.luau` (Lune) loads `Place1.rbxl` into RbxSim, replaces the source of
   `ServerScriptService.Services.FishingService` with `return {}` (like
   `tests/stage2_client.test.luau`), starts the server and, for each scenario, adds a fresh
   player on the device (see [Devices](#devices)), waits for the base, the character and the
   HUD plus `settle` seconds (4.2 s: the welcome toast is gone), runs the scenario — the REAL
   client controllers react to what the harness (playing the server) sends — and dumps the
   player's PlayerGui at the requested times (60 fps virtual time in between). Scenarios
   with `server = true` (the catch timelines) run in a second sim whose FishingService is
   live: the harness plays like a person (taps the real buttons) and the server does the
   rest. Every player is an R15 rig (RbxSim `rig = "R15"`) on base 1 (`BaseConfig.
   RandomAssignment` is switched off in the sims: the backdrop is base 1's pier), and while a
   Tool is equipped RbxSim's Animator stand-in holds Roblox's "toolnone" pose
   (`FisherPoses.Hold`, like the Animate script). Every frame records the own avatar as the
   client sees it; scenarios with `world = true` record the whole 3D world
   (`gui/world_capture.luau`, see [World](#the-3d-world-in-the-previews)). Script errors and
   warnings of the run go into the dump and are printed.
2. `tools/preview/gui_render.py` draws each frame at the device resolution, 2x supersampled:
   the backdrop, the 3D world (the avatar, FX, ambient life — `gui/solids.py` with a z-buffer
   against the backdrop's depth, then the 2D world items of `gui/world.py`), every GuiObject in
   draw order (`gui/paint.py`, text in `gui/text.py`), then the CoreGui chrome
   (`gui/backdrop.py`), and downsamples. It runs the checks (`gui/checks.py`) on every frame
   and writes `checks.txt`.
   If any dump had a script error it still writes everything, then prints `SCRIPT ERRORS in …`
   and exits with code 2: those previews do not show the real game.
   The dumps run in parallel Lune processes (`--jobs`, default = CPU count, max 8, split
   across devices) and every frame of every dump is rendered in one process pool.

Speed (4 cores, nothing else running): `--all` takes ~10 min (~6 min of dumping 48 scenarios
on 5 devices — the R15 rigs and the avatar capture cost ~13 % of it, the living world of the
client most of the rest —, ~3.5 min rendering 118 stills, 50 sheets, 13 bursts and the layout
overlays; `--no-checks-devices` saves ~3 min); `--timeline` ~2.3 min for its 7 scenarios; one
scenario on one device ~2–4 s to dump (a real-server session ~10–16 s), a still ~0.3 s, the
avatar ~0.02 s of it, a world frame with ~600 moving parts ~0.4 s, a full-screen catch frame
~1.5 s (the sunburst). New backdrops (a resolution, a camera or a variant) ~2–5 s once each.

### Devices

| device | screen | input | safe area (HUD) |
|---|---|---|---|
| `phone` | 844x390 | touch | full width, y 58..390 |
| `phone_notch` | 844x390 | touch | insets left 47, right 47, bottom 21: x 47..797, y 58..369 (750x311) |
| `phone_small` | 667x375 | touch | full |
| `tablet` | 1024x768 | touch | full |
| `desktop` | 1280x720 | keyboard + mouse | full |
| `console` | 1920x1080 | gamepad | full |

The insets model Roblox's `ScreenInsets.CoreUISafeInsets` on a notched iPhone in landscape:
a ScreenGui that keeps them (the HUD) is laid out inside the safe area below the 58 px top
bar; `DeviceSafeInsets` (and `IgnoreGuiInset = true`, taken as the same) keeps only the
device insets, `None` is the whole screen. RbxSim knows no insets, so `gui_dump.luau` hooks
the sim's `AbsoluteSize`/`AbsolutePosition` of such layers (`installSafeArea`) — the
controllers measure the same 750x311 HUD that is drawn. The chrome (top-bar buttons, hotbar,
Jump, thumbstick) is drawn inside the device safe area too, with the rounded screen corners,
the sensor housing and the home indicator. **To verify once on a real notched phone**: where
Roblox really puts the touch controls and the top-bar buttons (the model assumes inside the
safe area).

### Scenarios (`tools/preview/gui_scenarios.luau`)

| scenario | state | sheet |
|---|---|---|
| `spawn_base` | the base arrives: the «ТВОЯ БАЗА» banner, then it flies into the badge (stills 0.6 / 2.25 / 2.9 s) | 0..3.2 s @ 8 fps, status + banner |
| `no_base` | all bases taken: «Ждём базу…» | |
| `start` | just spawned, rod in the backpack, newcomer hint | |
| `rod_far` | rod in hand, far from the fishing spot: «КУДА ИДТИ?» 🧭, hint, guide beam | |
| `spot_take` | at the spot, rod in the backpack: «ВЗЯТЬ» | |
| `take_rod` | tap «ВЗЯТЬ»: the rod in hand, the button pops into «ЗАБРОСИТЬ» | 0..0.8 s, action area |
| `spot_ready` | at the spot with the rod: «ЗАБРОСИТЬ» | 0..4 s @ 6 fps (idle shine) |
| `cast` | tap «ЗАБРОСИТЬ» → waiting | 0..1 s, action area |
| `press_sink` | «ЗАБРОСИТЬ» held down (touch-down only): the UI v5 sim press — the button squashes to 0.9 and its face darkens a step, the outline and the caption pill stay (the scenario keeps its older name) | 0..0.3 s, action area |
| `waiting` | line in the water: the Water «ЖДЁМ…» (bobber, ripples, dots, 1–2 nibbles) + «СМОТАТЬ» | 0..2.4 s, action area |
| `bite` | «КЛЮЁТ!» slam, «!» glyphs, Sun edges, one 0.45 s beat + «ПОДСЕЧЬ!» | 0..1.2 s |
| `minigame_common` … `minigame_mythic` | the minigame for each rarity, needle mid-run (Epic 1/2, Mythic 2/3 hits done) | legendary: 0..1 s |
| `hit`, `hit_perfect`, `hit_super` | a hit: zone jumps, pip fills (off-centre / perfect / the second Mythic hit) | 0..0.9 s |
| `miss`, `minigame_timeout` | a miss: «МИМО!» / «ВРЕМЯ!» on the ghost (🐟 swims off), the hint as it leaves (miss stills 0.25 / 0.9 s) | miss 0..1.2 s |
| `lost_late`, `denied_far` | hints of a lost fish / a refused cast | |
| `catch_win` | the winning tap (Legendary, time 0 = "Caught"): win morph (needle where tapped) sinking away, «ПОЙМАНА!» left of the character, tension, the landing shockwave and edge glow (no full-screen flash), rays around the fish, giant title, the card | 0..2.6 s (whole screen) |
| `catch_hold` | the winning tap before the server answers: the needle freezes gold where tapped, the zone glows, the panel bumps | 0..0.6 s, minigame |
| `catch_common`, `_rare`, `_epic`, `_legendary`, `_mythic` | catch card per rarity (time 0 = the card with its name is visible; stills after its last beat, Common at «НОВИНКА!» too, Rare / Legendary / Mythic also while «+N 💰» flies out beside the card). The first Common is a NEW species: its small fanfare | common 0..2.2 s, legendary 0..3.0 s, mythic 0..3.2 s (whole screen) |
| `catch_common_again` | a known Common (the second Карасик): calm — no dim, no confetti, no «+N 💰», 0.2 s beats | 0..2.3 s (whole screen) |
| `catch_gold`, `catch_neon`, `catch_rainbow` | catch card with a mutation (the base price ticks, stamp, «×N», recount with the party, outline) | rainbow 1.4..3.0 s |
| `catch_skip` | a tap during the reveal (Epic) shows every beat at once | 0..0.5 s |
| `catch_close` | tap closes the settled card: the card itself flies into the counter shrinking to a speck (the first catch: «Улов: 0» pops in), 🐟 ★ beside it, +1 in the rarity colour ≈ 0.33 s after the tap (stills 0.2 / 0.36 s) | 0..1 s, whole screen |
| `toast_info`, `toast_success`, `toast_warning`, `toast_danger` | one toast of each kind | success 0..0.8 s |
| `toast_stack` | three toasts (the cap), then the oldest leaves | 3..4.4 s |
| `home_cooldown` | «ДОМОЙ» pressed, cooldown draining | 0..0.8 s |
| `far_tap` | tap «КУДА ИДТИ?» far from the spot: no cast, the hint pops again, the guide beam flares | 0..0.8 s, action area + hint |
| `minigame_cue` | a first-timer's minigame: the needle in the zone, 👆 taps «ЛОВИ!» | |
| `hit_mega` | the third hit before the last one (a 4-hit payload): «МЕГА!» in rainbow | |
| `toast_legendary`, `toast_mythic` | someone else's rare catch: the Gold 🌟 / rainbow 🌈 toast in two lines — who (small) over what (big, gold / running rainbow), Mythic's rainbow screen edges (Notify kinds "Legendary" / "Mythic") | 0..0.9 s, toasts |
| `toast_minigame` | a broadcast arrives during the own minigame: on a phone it waits, on a PC / tablet it steps aside while «МИМО!» rises; it comes out once the miss ghost has gone (stills 0.5 / 2.2 s) | |
| `toast_long` | a long toast wrapping to two lines | |
| `selftest` (not in `--all`) | a synthetic ScreenGui, one cell per renderer feature — check the renderer here | |

Bursts (`--bursts`; `--all` makes them on the phone): 0..0.8 s at 30 fps of `bite`, `take_rod`, `hit`,
`hit_perfect`, `hit_super`, `miss`, `catch_common`, `catch_legendary`, `catch_mythic`,
`catch_gold`, `catch_rainbow`, `catch_close` (the `BURSTS` table in `gui_dump.luau`; a
scenario's own `burst` field wins), cropped to the scenario's sheet `roi`.

Built into `gui_dump.luau` (they need the real server and the world capture; not in `--all`,
rendered by `--timeline` or by name):

| scenario | what | timeline |
|---|---|---|
| `catch_timeline` | a real Legendary catch (Акулёнок) from the winning tap (title stage, card, close, trophy replay) | 0..8 s @ 6 fps + burst |
| `catch_timeline_common` | a real Common catch (Карасик) | 0..5.5 s @ 6 fps + burst |
| `catch_timeline_mythic` | a real Mythic Rainbow catch (Рыба-дракон) | 0..9 s @ 6 fps + burst |
| `fishing_timeline` | a whole real session with the avatar (Epic Рыба-меч) from the tap «ЗАБРОСИТЬ»: wind-up and throw, the wait (shadow, nibbles), the bite, the strike, the fight with the bent rod and the taut line, the winning tap, the leap, both arms up with the fish, the card (the bite comes 2.6 s after the landing: `h:fixBiteDelay`) | 0..9.5 s @ 4 fps + `_world` (no HUD) |
| `trophy_hold` | after the card has closed: the Legendary trophy over the head bobs and flops (FishLife), the nameplate beside it, both arms hold it up (cropped to the fisher, no x-ray) | 0..3.2 s @ 5 fps |
| `lost_fish` | a Rare fight, then a tap outside the zone: «МИМО!», the line flashes red and goes slack, the fish dives off, the shadow flees, the fisher slumps and shakes his head (the minigame panel stands beside him on every device — on a tablet and a PC too since r4, UX-01; `_world` shows the world alone) | 0..3.4 s @ 8 fps + `_world` |
| `ambient_pier` | the living world from the pier tip, nothing else happening (stub server): a fish jumps (`AmbientController.JumpSoon` at 1.2 s), the pier gull swoops (`SwoopSoon`), schools, dragonflies, foam rings, swaying flags, the windmill and the Ferris wheel turn | 0..6 s @ 4 fps + `_world` + `_motion` |

World + HUD scenarios in `gui_scenarios.luau` (`server = true`, `world = true`, not in `--all`; by
name): `bite_world` (a real bite: the bobber dives above the «КЛЮЁТ!» plate), `minigame_world` (a
real Legendary minigame: on a phone the panel stands beside the reeling bobber), `nibble_world`
(the own bobber's nibble: the dip, ring, drops and «?»). `trophy_chip` (`world = true` only, IN
`--all` since UI v5 so its gap to the Home column is checked on every device): someone else's
Legendary pillar on the next pier, off-screen — the broadcast and the 🌟 chip at the screen edge on
its side; `FishingFxController.OtherTrophy` is fired directly, with the player itself as the
catcher.

Fishing world FX (v3, `server = true`, `world = true`, not in `--all`; by name, with `--bursts`):
`fx_cast` (wind-up, the tip's whip trail at the release, the flight on a curved line, the landing
plop; burst 0..1.6 s), `fx_wait` (the slack line, the fish shadow swimming in and circling; sheet
0..4.8 s @ 5 fps), `fx_bite` (the shadow lunges, the line snaps taut on every jerk), `fx_reel`
(Legendary fight: the shadow thrashes, the taut line trembles), `catch_landing` /
`catch_landing_mythic` (a real Legendary / Mythic Rainbow catch around the landing, burst
0.6..1.6 s over the whole screen: the crisp burst at the fish, no screen wash). Their `roi` is a
fixed part of the screen — `{ frac = { x0, y0, x1, y1 } }` (fractions of the screen; world FX
have no GUI path) — and may be mixed with GUI paths.

Scenarios find widgets by name only (`HUD.Fishing.ActionArea.ActionButton`, `HUD.Fishing.CatchCard`,
`HUD.RightButtons.HomeButton`, ...), so they survive restyles; a missing or hidden widget is a
warning, not a crash (clicks are forced). A scenario is

```lua
{
	name, desc, run = function(h) ... end,   -- time 0 = when run returns
	still = t | { t, ... },                   -- still times (default 0.6)
	sheet = { from, to, fps, roi = { paths }, margin },
	burst = true | false | { from, to, fps, roi, margin },  -- default 0..0.8 s @ 30 fps
	timeline = { from, to, fps, tail?, roi? },-- frames for the _timeline composite (full screen
	                                          -- unless roi); tail = s kept after the last beat (0.7)
	worldView = true | { roi, margin, cell }, -- also _world: the timeline frames without the HUD
	xray = false,                             -- no x-ray boxes on the timeline
	server = true,                            -- the real FishingService (a second sim)
	world = true,                             -- record the whole 3D world (gui/world_capture.luau)
	ambient = false,                          -- … without the ambient life
	during = function(h) ... end,             -- keeps playing while the frames are dumped
	beats = { spec, ... },                    -- replaces DEFAULT_BEATS; extraBeats adds to them
	fresh = true, settle = s, standard = false,
}
```

The sheet region is the union of the `roi` objects' screen boxes over all sheet frames plus
`margin` x screen height (none listed or none visible = the whole screen).

`during` runs as a coroutine after time 0: each of its harness steps (`h:advance`, `h:click`,
`h:waitFor` …) is a step of the frame loop, so a scenario can tap and wait while its frames are
dumped (`fishing_timeline`: time 0 = before the cast tap, the bite, the strike and the hits come
in `during`).

The harness `h` (documented in `gui_scenarios.luau`'s header and `gui_dump.luau`):
`h:advance`, `h:gui`, `h:visible`, `h:shown(path)` (visible AND not scaled to nothing or
faded out), `h:waitFor`, `h:waitVisible`, `h:click`, `h:press`, `h:serverSays(state, data)`
(FishingState), `h:notify(text, kind)`, `h:giveRod`, `h:equipRod`, `h:standAtSpot`,
`h:standFar`, `h:config`, `h:minigame(rarity, extra)`, `h:caught(fish, total)`, and for
`server = true` scenarios:

* `h:playCatch(fish, opts?) -> FishData` — a whole real catch: `h:readyReal(fish)` (every roll
  gives `fish`, onto the spot facing the lagoon, rod in hand), `h:castAndHook(opts)` (tap
  «ЗАБРОСИТЬ», wait for the bite, tap «ПОДСЕЧЬ!» after `opts.reaction` s (0.3); returns the
  "Minigame" event), `h:playMinigame(mg, opts)` (tap when the needle crosses the zone at
  `opts.aim`, -1..1 of the half-width, 0 = the centre; `opts.miss` = one tap well outside the
  zone, not before `opts.after` s). Returns right after the WINNING (or missing) tap (make that
  time 0). `fish = { Id, Mutation?, Kg? }`.
* `h:forceFish(fish) -> FishData` — every roll gives this fish (`FishingService.RollFishForTest`).
* `h:fixBiteDelay(s)` — the bite comes `s` after the landing (restored after the scenario).
* `h:stateEvents() -> { { time, state, data } }`, `h:stateAfter(count, state)` — the
  FishingState events this client got.
* `h:clientModule(name)` — the own client's controller module (`AmbientController`,
  `FishingFxController`, `FisherAnimController` …).
* `h:poseLikeBackdrop()` (the character onto the FishingSpot, facing the lagoon), `h.world` —
  the world capture of a `world = true` scenario.

#### Beats

A beat is a named moment found automatically while the frames are dumped (every 60 fps
step, from time 0); bursts and timelines draw them as a ruler under each frame: the window as
an axis, every beat as a numbered tick (lit once passed), the frame time as a white cursor,
`»` the beats since the previous frame, and the frame's fill and how much of each world
object the HUD hides. The composite's header lists `n·name time`. Default beats
(`DEFAULT_BEATS` in `gui_dump.luau`), in the UI v2 vocabulary:

| beat | when |
|---|---|
| `caught` | the client got FishingState "Caught" |
| `win` | `FxMinigameWin` is shown (UI v2 FUI-01) |
| `leap` / `held` / `held gone` / `pillar` | the world: the Leap model / HeldFish appear, HeldFish vanishes, `PillarCore` appears |
| `landing` | `FishingFxController.OwnFishLanded` fired (UI v2 WFX-02) |
| `flash` | an `FxFlash` is shown (the bite's sun flash; a catch landing has none) |
| `shock` | an `FxShockGlow` is shown (the disc of `UiFx.shockwave`: the landing hit at the fish) |
| `title` | `Fishing.TitleSlam` shown (the giant rarity word of Epic+) |
| `card`, `banner`, `name` | `CatchCard`, `CatchCard.Banner.RarityLabel`, `CatchCard.NameLabel` shown |
| `new`, `chips` | `CatchCard.NewStamp` («НОВИНКА!»), `CatchCard.InfoLabel.Weight` shown (the card's beats are ≥ 0.25 s apart: tests/fishing_ui_style "catch card beats") |
| `price` | `CatchCard.InfoLabel.Price.Label` stopped changing (the count-up landed) |
| `mutation` | `CatchCard.MutationLabel` or `CatchCard.MutationStamp` shown |
| `close` | `CatchCard` hidden again |
| `fly` | an `FxFly` is shown (the 🐟 flying into the counter) |
| `+1` | `Status.CatchCounter.Label` changed |
| `bite`, `zone`, `lost` | the client got FishingState "Bite" / "Zone" (a hit) / "Lost" |
| `word` | an `FxFloat` is shown (the hit word) |
| `miss ghost` | `FxMinigameMiss` is shown |

A spec is `{ name, appear = path | { paths } }`, `{ name, appearNamed = "FxFlash" }`,
`{ name, disappear = path }`, `{ name, change = path }` (Text differs from time 0),
`{ name, settle = path }` (Text last changed), `{ name, state = "Caught" }`,
`{ name, event = "HeldFish", kind = "appear" | "disappear" | "signal" }` (world) or
`{ name, fn = function(h) -> bool }`. When a widget is renamed, update `DEFAULT_BEATS` or pass
`beats` / `extraBeats` in the scenario.

### The 3D world in the previews

`gui/world_capture.luau` records, at every 60 fps step of the capture window, what the
player's own CLIENT sees in the world, and `gui_render.py` draws it over the backdrop, under
the HUD. Two modes:

* **avatar** — every scenario without `world = true`: only the own character (its posed body,
  the rod in hand, a held fish), drawn standing on the FishingSpot facing the lagoon (where the
  old blocky stand-in stood) at the default camera. The standard stills show the real avatar
  in whatever pose the real controllers give it (the "toolnone" arm with the rod, the
  `castPress` wind-up after the tap…).
* **world** — `world = true`: the avatar, the FX, the ambient life, the 2D items below, and
  the client's `Workspace.CurrentCamera` is put on the capture camera on every step, so the
  controllers' own screen maths (`Camera:WorldToScreenPoint`: where the catch card is born,
  whether a widget hides the own bobber) and AmbientEngine's view culling agree with the
  drawing.

**Solids** (`gui/solids.py`: render.py's rasterizer with a z-buffer, lit by render.py's sun,
fogged by the place's atmosphere and colour-graded like the backdrop, with outlines; per pixel
against the backdrop's own depth, so the pier rail hides the feet and the fisher hides the
bobber behind his head):

* every character's body parts as the client sees them — FisherAnimController's joint
  Transforms (RbxSim's forward kinematics per client view): wind-up, the throw, the wait with
  the left hand at the reel, the bite, the strike, the reel, both arms up with the fish, the
  lost slump. RbxSim avatars have no appearance: the classic look by part name (yellow skin,
  blue shirt, green trousers) and a brown hair stand-in (a cap and the back of the head) so the
  head's turn reads from behind;
* the Tool — the rod bent by FisherRod (client-local Weld C0s), the line's TipAttachment with it;
* the HeldFish model (FishLife's bob and flop: client-local C0s), the leap / dive copies;
* every BasePart in the player's `Workspace.FishingFx` (bobber, the fish shadow — a SpecialMesh
  «Sphere» is an ellipsoid —, drips, the pillar …);
* ambient life (world mode; `ambient = false` turns it off): the parts of the client's
  `Workspace["Ambient (client)"]` in view (schools, jumping fish, gulls, butterflies,
  dragonflies …) and the map's **movers** — the parts of every Model / BasePart that
  AmbientWorld moves (attributes `Sway` / `Bob` / `Spin` / `Pulse`, chase-light bulbs
  `…Bulb<n>`; not the `Drift` clouds) within `Capture.MOVER_RANGE` studs of the spot (Sway /
  Pulse 220, Bob / bulbs 320, Spin 650: the windmill and the Ferris wheel), at their client-local
  CFrame and transparency. The dump lists their static data once (`scene.movers`) and their rest
  geometry (`scene.exclude`, world coordinates); the backdrop of a world dump is rendered
  without them, so nothing is drawn twice.
* parts under the water surface are mixed with the water colour by the length of the ray under
  the surface (`WATER_CLEAR` 6 studs: the shadow half a stud down reads, deep things fade);
  transparent parts blend far to near; Neon parts are unlit and glow.
* LEGO studs: only movers keep the studs they have in the place (Plastic + their saved surfaces);
  avatar, FX and ambient parts never get studs (RbxSim's `Instance.new("Part")` reports Studs on
  top — the capture does not pass surfaces on).

**2D items** (`gui/world.py`, painted after the solids, hidden where the scene or a solid is
nearer than the item's nearest point by a margin — so the bobber and the leap behind the
player's head are hidden, while rings on the deck are not cut):

* SurfaceGui → its GUI at the canvas size, warped onto the projected face (back faces culled):
  foam rings, jump rings;
* BillboardGui → laid out at "studs x px-per-stud + px" at its depth, StudsOffset(WorldSpace),
  SizeOffset, MaxDistance: the trophy's nameplate, the «?» of a nibble;
* Beam → a ribbon along the Bezier (CurveSize0/1 along the attachments' WorldAxis), Width0/1,
  Color / Transparency along it — the line leaves the bent rod's live tip; Trail → the ribbon
  of its attachments' last Lifetime seconds, Color / Transparency / WidthScale by age;
* ParticleEmitter → simulated (RbxSim has none; `Emit` is hooked): Rate while Enabled and
  every `Emit(n)`, spawned in the parent part's box (or at the attachment), EmissionDirection +
  SpreadAngle, Speed, Lifetime, Acceleration, Drag, LockedToPart; dots by Size, Color and
  Transparency over life (sparkle textures as 4-point stars, smoke as soft discs, others as
  confetti squares); deterministic;
* PointLight → a faint glow.

Camera: the backdrop's — the Roblox default third-person camera 12.5 studs from the focus,
18 deg down, vertical FOV 70, focus 4.6 studs above the top of the own FishingSpot, looking
along the base's LookVector — plus the local Humanoid's `CameraOffset` (in the character's
frame; world mode). The dump writes the camera per frame and the solids in the spot frame
(right, up, forward from the top of the FishingSpot), and the backdrop is rendered of base 1's
pier with that very camera (cached per camera and variant, so a `CameraOffset` gets its own
backdrop). `h:poseLikeBackdrop()` stands the rigged character on the spot: its root
HipHeight + half its height above the top, facing the lagoon.

Avatar mode (every scenario without `world = true`): the body is drawn moved onto the FishingSpot
wherever it really stands, and the client's `Workspace.CurrentCamera` follows the real body the
same way (placement⁻¹ × the capture camera, like Roblox's follow camera), so the controllers'
own-character keep-out (`FishingLayout.fisherBox`) sees the fisher where the drawing shows him.

X-ray (timelines and timeline bursts, unless `xray = false`): dashed boxes over the HUD for the
fish models (the leap arc as dots), the pillar, the halo and the nameplate, each with how much
of it the HUD hides (HUD opacity >= 0.6), also printed in the ruler: `HeldFish 100% under HUD`
is the card hiding the trophy. `--no-world` draws the plain backdrop, `--no-hud` only the
world; `worldView` scenarios get the HUD-less frames as `_world.png` anyway.

Not drawn: Highlights, Decals/Textures (no face on the head), mesh shapes other than the
sphere (their box), accessories (the hair is a stand-in), camera shake / FOV punches (the GUI
part of them is), the terrain water's ripples and waves, the Drift clouds' drift (they stay in
the backdrop). Speed: an avatar frame costs ~0.05 s, a world frame with ~600 movers and ambient
parts ~0.4 s.

### Checks: fill, layout safety, text floor

`gui/checks.py`, on every dumped frame (layout and text on the stills); results in the stills'
captions, the sheet labels, the rulers, `checks.txt` / `checks.json` and the summary printed
at the end.

* **Fill** (GPU cost, RND-03): the summed on-screen area of every visible quad divided by the
  screen area — a quad counts whenever Roblox draws it, however transparent: the background,
  image or ViewportFrame of a GuiObject, a text label's box, and every Border UIStroke as the
  rect of the box grown by its thickness; rotated quads are clipped to the screen as polygons.
  1.0x = one screen of alpha-blended pixels. On 844x390 (`phone`, `phone_notch`) and 667x375
  (`phone_small`, the oldest GPUs) a peak over **2.5x** prints a warning. `checks.txt` gives each scenario's peak (with the three biggest
  contributors) and median.
* **Layout safety** (RND-02): widgets are the children of each ScreenGui and of `HUD.Fishing`
  (`CONTAINERS`): `HUD.Status`, `HUD.RightButtons`, `HUD.Toasts`, `HUD.Fishing.ActionArea`,
  `.Hint`, `.BiteAlert`, `.Minigame`, `.CatchCard`, ... A widget's shape is the union of the
  rounded rects of what it draws — backgrounds, images, Border strokes (grown by their
  thickness), and for a text label without a background the ink box of its text — so
  overhanging icons and caption ribbons count and invisible containers do not. Skipped:
  effects (any path part starting with `Fx`) and full-screen layers (>= 45 % of the screen:
  dims, ray holders). Every pair of widgets, and every widget against the CoreGui chrome
  (`gui/backdrop.chrome_shapes`: Jump and the thumbstick as circles, the hotbar, the top-bar
  buttons, the desktop chat window and player list), closer than **16 px** is reported with the
  gap (negative = overlap) between the closest points; a glow ring (`FxRing`) reaching into
  Jump or the thumbstick is reported too. `--all` also dumps the standard set on
  `phone_notch`, `phone_small` and `tablet` for the checks only (`--no-checks-devices` skips
  them); their failing stills are drawn as `_layout.png`.
* **Text floor**: visible text at rest (UIScale ~1) drawn under 12 px after TextScaled fitting.

### gui_dump.luau

```
lune run tools/preview/gui_dump.luau --device phone|phone_notch|phone_small|tablet|desktop|console \
    --scenario a,b|all --out DIR [--place Place1.rbxl] [--at T,T] [--sheets] [--bursts] \
    [--times A:B:FPS] [--no-stills] [--check] [--verbose]
lune run tools/preview/gui_dump.luau --list
```

`--check` compares the dump's layout with RbxSim's `AbsolutePosition/AbsoluteSize` and prints
the differences (expected only where RbxSim is approximate: list alignment, UIScale, rotation).

The dumper lays the GUI out itself (RbxSim ignores UIScale, rotation and list alignment):
UDim2 Size/Position, AnchorPoint, SizeConstraint, UISizeConstraint, UIAspectRatioConstraint
(FitWithinMaxSize / ScaleWithParentSize + DominantAxis), UIPadding, UIListLayout (direction,
both alignments, padding, LayoutOrder/Name sort), UIGridLayout (cell size/padding, alignment,
FillDirectionMaxCells), ScrollingFrame canvas, ScreenGui insets (`ScreenInsets` None = the
whole screen, DeviceSafeInsets / `IgnoreGuiInset` = the device safe area, CoreUISafeInsets =
the safe area below the 58 px top bar). Then:

* **UIScale** scales the object and its whole subtree visually about the object's AnchorPoint —
  offsets, corner radii, stroke thickness and text sizes included; nested scales multiply.
* **Rotation** turns the object and its subtree about the object's (scaled) centre; rotations
  accumulate.
* **Clipping**: ClipsDescendants, CanvasGroup and ScrollingFrame clip descendants to the
  object's screen rectangle — ignored when the object or an ancestor is rotated (Roblox rule).
  CanvasGroup's GroupTransparency multiplies the opacity of its subtree.
* **Draw order**: ScreenGuis by DisplayOrder; `ZIndexBehavior.Sibling`: a parent before its
  children, siblings by ZIndex then child order; `Global`: everything by ZIndex then tree order.

The same layout (`dumpTree`) lays out BillboardGuis and SurfaceGuis of the world capture.

One JSON per device and scenario (version 2): `{ version, scenario, desc, device, viewport,
touch, inset, safe = [left, right, bottom], sheet, burst, timeline, camera, beats = [{name, t}],
events = [{name, kind, t}], frames = [{ t, still, sheet, burst, timeline, tools =
[{name, equipped}], objects = [...], world? = { cam, items, marks } }], errors, warnings }`.
Objects are the effectively visible GuiObjects in draw order, in screen pixels:
`path, class, name, z, x, y, w, h` (the box before rotation; rotate about its centre),
`rot, k` (accumulated rotation and UIScale), `clip, alpha, bg, bgT, radius / radii`
(UICorner in px), `border` (legacy, only without UICorner and a Border UIStroke),
`strokes` (`color, t, offset, tr, target border|text, pos Outer|Center|Inner, join, grad`),
`grad` (UIGradient: `c` colour keypoints, `a` transparency keypoints, `rot, off, type, tile,
scale`), `text` (`s, rich, c, tr, sc, st, scaled, size, wrap, xa, ya, font, weight, style, lh,
min, max, pad, trunc, graphemes`), `image`, `viewport` (`models` = name, fish id, mutation,
title, rarity), `auto` (AutomaticSize — flagged, not applied). The full field list is in the
script's header; the world items are listed in `gui/world.py`. Lune encodes an empty list as
`{}` — read lists with that in mind.

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
| `--all` | | the standard set (every scenario but `selftest` and the timelines), stills + sheets + bursts, overviews, the checks on 5 devices |
| `--scenario LIST` | | dump and render these scenarios |
| `--timeline` | | the catch timelines (default device `phone`) |
| `--devices LIST` | `phone,desktop` | `phone`, `phone_notch`, `phone_small`, `tablet`, `desktop`, `console` |
| `--sheets` / `--bursts` | off (`--all`: sheets on, bursts on the first device) | also the animation sheets / the 30 fps bursts on every device |
| `--at T,T` / `--times A:B:FPS` | | still times / sheet window for every scenario |
| `--out DIR` | | output directory (required) |
| `--bg MODE` | `pier` | `pier` (rendered game frame), `plain` (sky/sea gradient), or an image path (cover-fitted) |
| `--no-chrome` | | no Roblox CoreGui overlay |
| `--no-world` / `--no-hud` | | world dumps: no world FX / only the backdrop, world FX and chrome |
| `--gif` | | also animated GIFs of the bursts and timelines |
| `--no-checks-devices` | | `--all` without the check-only devices |
| `--no-caption` | | no caption bar under the stills |
| `--no-overview` | | no overview images |
| `--ss N` | 2 | supersampling |
| `--place FILE` | `Place1.rbxl` | the place to dump (and to render the backdrop from) |
| `--jobs N` | CPU count (max 8) | parallel Lune dumps / render workers |
| `--list`, `--selftest`, `-v` | | list scenarios / check the geometry and checks / print every dump log line |

**Backdrop** (`--bg pier`): `render.py`'s perspective renderer at the device resolution — the
Roblox default third-person camera (12.5 studs behind the head, 18 deg down, vertical FOV 70;
a world dump's per-frame camera when it has one) over base 1's FishingSpot, looking over the
lagoon. The fisher on the spot is drawn per frame from the dump (the real posed avatar, see
[the 3D world](#the-3d-world-in-the-previews)); the backdrop is the empty pier (`_noav` in the
cache) and, for world dumps, also without the map's movers (`_x<hash>`: `scene.exclude`). Only
an old dump without solids still gets the blocky stand-in avatar (classic R6 colours, bamboo
rod raised). Parts/terrain come from `export_parts.luau` / `export_terrain.luau`; the image,
its depth per pixel (the 2D items' occlusion) and per supersampled pixel (the solids' z test;
the sky is +inf) and the place's look for the solids (`ctx_<key>.json`: base 1's spot, grading,
fog, water) are cached in `tools/preview/gui/.cache/` (ignored by version control; key = place
path, size, mtime, `backdrop.VERSION` (bumped when the export or the depth changes: 4 = stud
surfaces, 5 = sky depth +inf and the variants) + resolution + camera + variant;
`GUI_PREVIEW_CACHE` moves it), ~2–5 s per new resolution, camera or variant. The pier is drawn
with its LEGO studs like the map renders. If it cannot be rendered, `docs/preview_pier.png` is
cropped instead (no occlusion and no solids then).

**CoreGui chrome** (drawn over the HUD at 80 % opacity, so overlaps stay visible; the shapes
come from `gui/backdrop.chrome_shapes`, shared with the layout check): the 58 px top bar
(Roblox menu button, chat/more pill); on desktop the open chat window (top-left, 360x180) and
the player list (top-right); the hotbar — 60 px slots centred, 5..65 px above the bottom, one
per tool from the dump (number, wrapped name, white frame on the equipped one) — only while the
game keeps the Backpack CoreGui on (the frame's `hotbar` flag: since v3 HudController switches it
off, so there is no hotbar in the previews and the layout check has none either); on touch
devices the classic thumbstick and the Jump button: short side <= 500 px: 70 px at 25..95 px
from the right and 20..90 px from the bottom (thumbstick mirrored on the left); bigger
screens: 120 px at (W-170..W-50, H-210..H-90) (thumbstick at x 60..180). On `phone_notch`
everything moves inside the safe area, plus the rounded corners, the sensor housing and the
home indicator.

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
* Text: TextSize is the line height (the font's ascent + descent are scaled to it, so the em is
  TextSize / 1.219 for Montserrat and TextSize / 1.364 for Nunito); TextScaled picks the largest whole size <= MaxTextSize (100 without a
  UITextSizeConstraint) and >= MinTextSize whose text, wrapped at spaces, fits the box without
  splitting a word; if none fits, the min size is used, long words are split and the text may
  overflow (that is what MinTextSize 9 on «ДОМОЙ» avoids). Alignment X/Y, LineHeight,
  TextWrapped, TextTruncate AtEnd, MaxVisibleGraphemes (typewriter: the full layout, first N
  graphemes drawn), RichText tags stripped, UIPadding on the label.
* Font: the family from `FontFace.Family` — **Montserrat** (the UI font since UI v5, Roblox's
  rbxasset://fonts/families/Montserrat.json; variable, `FontFace.Weight` 100-900 — the UI's Heavy
  is 900) from `tools/preview/fonts/Montserrat.ttf`, and `FontFace.Style = Italic` from
  `Montserrat-Italic.ttf` (SIL OFL 1.1, `fonts/OFL-Montserrat.txt`; the Google Fonts variable
  files), or Nunito (200-1000) from `Nunito.ttf` / `Nunito-Italic.ttf` (`fonts/OFL.txt`) — the
  map's signs still use it; any other family is drawn with Montserrat (a one-time warning: Roblox
  maps the retired Gotham onto it). Characters the family lacks (★, ⏱ in Montserrat; → in Nunito)
  use DejaVu Sans Bold. Colour emoji are **Twemoji Mozilla**,
  the font Roblox itself ships (`content/fonts/TwemojiMozilla.ttf`; our copy:
  `tools/preview/fonts/TwemojiMozilla.ttf`, twemoji-colr 0.7.0, graphics CC-BY 4.0 — see
  `fonts/TWEMOJI-LICENSE.txt`): flat shapes, exactly what the game draws. Pillow cannot draw its
  COLRv0 layers, so `gui/twemoji.py` reads the font itself (cmap, COLR/CPAL, glyf/loca; no
  fontTools): every layer's quadratic outline is flattened and filled with the non-zero rule at 4x
  supersampling and composited in palette colours (~5 ms per emoji, cached). Emoji are drawn at the
  text's em (1 em advance, ascent 0.93 em, on the baseline), mixed with text in the same line; ZWJ
  and flag sequences fall back to their first code point. Without the font, Noto Color Emoji
  (`GUI_PREVIEW_EMOJI_FONT` overrides the path) stands in with a warning — rounder and glossier
  than the game.
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
flex layouts, UIPageLayout/UITableLayout, rich-text styling, TextBox placeholders, rounded
clipping of CanvasGroups; world FX only in `world = true` scenarios (see above for what is
drawn). Roblox's exact font metrics and legacy TextStroke width are approximations;
TextScaled sizes may differ from Roblox by a pixel or two. The notch insets and where the
touch controls sit on a notched phone are a model (see Devices). Treat the renders as faithful
for layout, colour and composition, approximate for text rasterisation and the 3D effects.
