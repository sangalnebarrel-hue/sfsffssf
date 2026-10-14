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

See the HUD exactly as a player would — on a phone (also a notched one and a small one), a
tablet or a PC — without Roblox Studio: still images of every HUD state, contact sheets of the
animations, 30 fps bursts of the punchy first 0.8 s, and catch timelines where the world FX
(the leap, the held fish, the pillar, confetti) play UNDER the HUD with a beat ruler under
every frame. Drawn over a real frame of the game (the pier view) with the Roblox CoreGui
chrome on top, plus automatic checks: layout safety (gaps to Jump, the thumbstick, the
hotbar and between widgets), GPU fill per frame and the 12 px text floor. Made for design
critique: everything is a PNG (and a text report).

```sh
# the standard set: 37 states x phone + desktop (stills, 17 animation sheets each, 12 bursts on
# the phone, 2 overviews) + the checks on phone_notch, phone_small and tablet (~6.5 min on 4 cores)
python3 tools/preview/gui_render.py --all --out /tmp/ui
# the catch timelines (real server, world FX under the HUD, beat rulers), phone, ~1.5 min
python3 tools/preview/gui_render.py --timeline --out /tmp/ui
python3 tools/preview/gui_render.py --timeline --devices phone,phone_notch --gif --out /tmp/ui
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
| `<device>/<scenario>_timeline.png` | catch timelines: every frame full screen with the world FX, x-ray boxes and a beat ruler (see below) |
| `<device>/<scenario>_layout.png` | a still with its layout-safety findings drawn: the gap in px between the closest points (red < 8 px, amber < 16 px, pink = a glow ring inside Jump/thumbstick) |
| `<device>/<scenario>_burst.gif`, `_timeline.gif` | with `--gif`: the same frames as an animation (real speed) |
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
   rest. Scenarios with `world = true` also record the client's world FX
   (`gui/world_capture.luau`, see [World FX](#world-fx-in-the-previews)). Script errors and
   warnings of the run go into the dump and are printed.
2. `tools/preview/gui_render.py` draws each frame at the device resolution, 2x supersampled:
   the backdrop, the world FX (world dumps), every GuiObject in draw order (`gui/paint.py`,
   text in `gui/text.py`), then the CoreGui chrome (`gui/backdrop.py`), and downsamples. It
   runs the checks (`gui/checks.py`) on every frame and writes `checks.txt`.
   The dumps run in parallel Lune processes (`--jobs`, default = CPU count, max 8, split
   across devices) and every frame of every dump is rendered in one process pool.

Speed (4 cores): `--all` takes ~6.5 min (~2.7 min of dumping 37 scenarios on 5 devices, ~4 min
rendering 74 stills, 34 sheets, 12 bursts and ~135 layout overlays; `--no-checks-devices`
saves ~2 min); `--timeline` ~1.5 min; one scenario on one device ~2 s to dump, a still
~0.3 s, a full-screen catch frame ~1.5 s (the sunburst).

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
| `spawn_base` | the badge right when the server assigns the base (welcome toast) | 0..1.2 s, status |
| `no_base` | all bases taken: «Ждём базу…» | |
| `start` | just spawned, rod in the backpack, newcomer hint | |
| `rod_far` | rod in hand, far from the fishing spot (hint) | |
| `spot_take` | at the spot, rod in the backpack: «ВЗЯТЬ» | |
| `take_rod` | tap «ВЗЯТЬ»: the rod in hand, the button pops into «ЗАБРОСИТЬ» | 0..0.8 s, action area |
| `spot_ready` | at the spot with the rod: «ЗАБРОСИТЬ» | 0..4 s @ 6 fps (idle shine) |
| `cast` | tap «ЗАБРОСИТЬ» → waiting | 0..1 s, action area |
| `waiting` | line in the water: «ЖДЁМ…» + «СМОТАТЬ» | |
| `bite` | «КЛЮЁТ!» alert + «ПОДСЕЧЬ!» | 0..1.2 s |
| `minigame_common` … `minigame_mythic` | the minigame for each rarity, needle mid-run (Epic 1/2, Mythic 2/3 hits done) | legendary: 0..1 s |
| `hit`, `hit_perfect`, `hit_super` | a hit: zone jumps, pip fills (off-centre / perfect / the second Mythic hit) | 0..0.9 s |
| `miss`, `minigame_timeout` | a miss: «Мимо!» / the time is up | miss 0..1.2 s |
| `lost_late`, `denied_far` | hints of a lost fish / a refused cast | |
| `catch_win` | the winning tap (Legendary, time 0 = "Caught"): win morph «ПОЙМАНА!», tension, landing flash, giant title, the card | 0..2.6 s (whole screen) |
| `catch_common`, `_rare`, `_epic`, `_legendary`, `_mythic` | catch card per rarity (time 0 = the card is visible; stills after its last beat) | common 0..1.8 s, legendary / mythic 0..2.7 s (whole screen) |
| `catch_gold`, `catch_neon`, `catch_rainbow` | catch card with a mutation (stamp, «×N», recount, outline) | rainbow 1.6..3.2 s |
| `catch_skip` | a tap during the reveal (Epic) shows every beat at once | 0..0.5 s |
| `catch_close` | tap closes the settled card: it shrinks towards the counter, 🐟 ✨ fly in, +1 | 0..1 s, whole screen |
| `toast_info`, `toast_success`, `toast_warning`, `toast_danger` | one toast of each kind | success 0..0.8 s |
| `toast_stack` | three toasts (the cap), then the oldest leaves | 3..4.4 s |
| `home_cooldown` | «ДОМОЙ» pressed, cooldown draining | 0..0.8 s |
| `selftest` (not in `--all`) | a synthetic ScreenGui, one cell per renderer feature — check the renderer here | |

Bursts (`--bursts`; `--all` makes them on the phone): 0..0.8 s at 30 fps of `bite`, `take_rod`, `hit`,
`hit_perfect`, `hit_super`, `miss`, `catch_common`, `catch_legendary`, `catch_mythic`,
`catch_gold`, `catch_rainbow`, `catch_close` (the `BURSTS` table in `gui_dump.luau`; a
scenario's own `burst` field wins), cropped to the scenario's sheet `roi`.

Built into `gui_dump.luau` (they need the real server and the world capture; not in `--all`,
rendered by `--timeline` or by name):

| scenario | what | timeline |
|---|---|---|
| `catch_timeline` | a real Legendary catch (Акулёнок) from the winning tap | 0..7 s @ 6 fps + burst |
| `catch_timeline_common` | a real Common catch (Карасик) | 0..5.5 s @ 6 fps + burst |
| `catch_timeline_mythic` | a real Mythic Rainbow catch (Рыба-дракон) | 0..8.5 s @ 6 fps + burst |

Scenarios find widgets by name only (`HUD.Fishing.ActionArea.ActionButton`, `HUD.Fishing.CatchCard`,
`HUD.RightButtons.HomeButton`, ...), so they survive restyles; a missing or hidden widget is a
warning, not a crash (clicks are forced). A scenario is

```lua
{
	name, desc, run = function(h) ... end,   -- time 0 = when run returns
	still = t | { t, ... },                   -- still times (default 0.6)
	sheet = { from, to, fps, roi = { paths }, margin },
	burst = true | false | { from, to, fps, roi, margin },  -- default 0..0.8 s @ 30 fps
	timeline = { from, to, fps },             -- full-screen frames for the _timeline composite
	server = true,                            -- the real FishingService (a second sim)
	world = true,                             -- record the world FX (gui/world_capture.luau)
	beats = { spec, ... },                    -- replaces DEFAULT_BEATS; extraBeats adds to them
	fresh = true, settle = s, standard = false,
}
```

The sheet region is the union of the `roi` objects' screen boxes over all sheet frames plus
`margin` x screen height (none listed or none visible = the whole screen).

The harness `h` (documented in `gui_scenarios.luau`'s header and `gui_dump.luau`):
`h:advance`, `h:gui`, `h:visible`, `h:shown(path)` (visible AND not scaled to nothing or
faded out), `h:waitFor`, `h:waitVisible`, `h:click`, `h:press`, `h:serverSays(state, data)`
(FishingState), `h:notify(text, kind)`, `h:giveRod`, `h:equipRod`, `h:standAtSpot`,
`h:standFar`, `h:config`, `h:minigame(rarity, extra)`, `h:caught(fish, total)`, and for
`server = true` scenarios:

* `h:playCatch(fish, opts?) -> FishData` — a whole real catch: onto the spot (posed like the
  backdrop's stand-in), rod in hand, tap «ЗАБРОСИТЬ», wait for the bite, tap «ПОДСЕЧЬ!» after
  `opts.reaction` s (0.3), then win the minigame by tapping when the needle crosses the zone
  at `opts.aim` (-1..1 of the half-width, 0 = the centre). Returns right after the WINNING tap
  (make that time 0). `fish = { Id, Mutation?, Kg? }`.
* `h:forceFish(fish) -> FishData` — every roll gives this fish (`FishingService.RollFishForTest`).
* `h:stateEvents() -> { { time, state, data } }` — the FishingState events this client got.
* `h:poseLikeBackdrop()`, `h.world` — the world capture of a `world = true` scenario.

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
| `flash` | an `FxFlash` is shown |
| `card`, `banner`, `name` | `CatchCard`, `CatchCard.Banner.RarityLabel`, `CatchCard.NameLabel` shown |
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

### World FX in the previews

`gui/world_capture.luau` records, at every 60 fps step of a `world = true` scenario,
everything in the player's `Workspace.FishingFx` (FishingFxController) and, in every
character, the HeldFish model and any emitter / trail / beam / billboard / light — and
projects it with the backdrop's camera into screen px. `gui/world.py` draws it over the
backdrop, under the HUD:

* fish models (Title attribute, or named HeldFish / Leap / Dive) → the `docs/gear` sprite over
  the model's projected box, along its nose direction; hidden while every part is invisible
  (LocalTransparencyModifier — the leap handoff);
* parts: Block (visible faces, lit), Ball, Cylinder (hull), Transparency x
  LocalTransparencyModifier, Neon unlit with a glow; a part with Transparency 1 only carries
  its SurfaceGui / emitters / trails;
* SurfaceGui → its GUI at the canvas size, warped onto the projected face (back faces culled);
* BillboardGui → laid out at "studs x px-per-stud + px" at its depth, StudsOffset(WorldSpace),
  SizeOffset, MaxDistance;
* Beam → a ribbon along the Bezier (CurveSize0/1 along the attachments' WorldAxis), Width0/1,
  Color / Transparency along it; Trail → the ribbon of its attachments' last Lifetime seconds,
  Color / Transparency / WidthScale by age;
* ParticleEmitter → simulated (RbxSim has none; `Emit` is hooked): Rate while Enabled and
  every `Emit(n)`, spawned in the parent part's box (or at the attachment), EmissionDirection +
  SpreadAngle, Speed, Lifetime, Acceleration, Drag, LockedToPart; dots by Size, Color and
  Transparency over life (sparkle textures as 4-point stars, smoke as soft discs, others as
  confetti squares); deterministic;
* PointLight → a faint glow.

Camera: the backdrop's — the Roblox default third-person camera 12.5 studs from the focus,
18 deg down, vertical FOV 70, focus 4.6 studs above the top of the own FishingSpot, looking
along the base's LookVector — plus the local Humanoid's `CameraOffset` (in the character's
frame). The dump writes the camera per frame in the spot frame (right, up, forward), and the
backdrop is rendered of base 1's pier with that very camera (cached per camera, so a
`CameraOffset` gets its own backdrop). The sim's character is lifted so its head matches the
stand-in's, and the rod is moved so its `TipAttachment` sits at the stand-in's rod tip — the
line, the cast, the leap and the held fish line up with the drawn avatar.

Occlusion: the backdrop's renderer also writes its opaque depth; a world pixel is hidden
where the scene (the stand-in avatar, the pier, the map; not the water) is nearer than the
item's nearest point by a margin — so the bobber and the leap behind the player's head are
hidden, as in the game, while rings on the deck are not cut.

X-ray (timelines and timeline bursts): dashed boxes over the HUD for the fish models (the leap
arc as dots), the pillar, the halo and the nameplate, each with how much of it the HUD hides
(HUD opacity >= 0.6), also printed in the ruler: `HeldFish 100% under HUD` is the card hiding
the trophy. `--no-world` draws the plain backdrop, `--no-hud` only the world.

Not drawn: Highlights, Decals/Textures, mesh shapes (their box), camera shake / FOV punches
(the GUI part of them is), terrain water ripples. The stand-in avatar does not move.

### Checks: fill, layout safety, text floor

`gui/checks.py`, on every dumped frame (layout and text on the stills); results in the stills'
captions, the sheet labels, the rulers, `checks.txt` / `checks.json` and the summary printed
at the end.

* **Fill** (GPU cost, RND-03): the summed on-screen area of every visible quad divided by the
  screen area — a quad counts whenever Roblox draws it, however transparent: the background,
  image or ViewportFrame of a GuiObject, a text label's box, and every Border UIStroke as the
  rect of the box grown by its thickness; rotated quads are clipped to the screen as polygons.
  1.0x = one screen of alpha-blended pixels. On 844x390 (`phone`, `phone_notch`) a peak over
  **2.5x** prints a warning. `checks.txt` gives each scenario's peak (with the three biggest
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
a world dump's per-frame camera when it has one) behind a blocky stand-in avatar (classic R6
colours, bamboo rod raised) on base 1's FishingSpot, looking over the lagoon. Parts/terrain
come from `export_parts.luau` / `export_terrain.luau`; the image and its depth buffer are
cached in `tools/preview/gui/.cache/` (git-ignored; key = place path, size, mtime + resolution
+ camera; `GUI_PREVIEW_CACHE` moves it), ~3 s per new resolution or camera. If it cannot be
rendered, `docs/preview_pier.png` is cropped instead (no occlusion then).

**CoreGui chrome** (drawn over the HUD at 80 % opacity, so overlaps stay visible; the shapes
come from `gui/backdrop.chrome_shapes`, shared with the layout check): the 58 px top bar
(Roblox menu button, chat/more pill); on desktop the open chat window (top-left, 360x180) and
the player list (top-right); the hotbar — 60 px slots centred, 5..65 px above the bottom, one
per tool from the dump (number, wrapped name, white frame on the equipped one); on touch
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
flex layouts, UIPageLayout/UITableLayout, rich-text styling, TextBox placeholders, rounded
clipping of CanvasGroups; world FX only in `world = true` scenarios (see above for what is
drawn). Roblox's exact font metrics and legacy TextStroke width are approximations;
TextScaled sizes may differ from Roblox by a pixel or two. The notch insets and where the
touch controls sit on a notched phone are a model (see Devices). Treat the renders as faithful
for layout, colour and composition, approximate for text rasterisation and the 3D effects.
