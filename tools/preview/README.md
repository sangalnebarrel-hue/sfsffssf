# Map preview renderer

Renders PNG previews of the map geometry in a `.rbxl` place file, so the map can be
checked visually without Roblox Studio. Two steps:

1. `export_parts.luau` (Lune 0.11) reads the place and writes every visible part as JSON.
   It also simulates what the server does at runtime (base spawning, see below).
2. `render.py` (Python 3 + numpy + Pillow) draws the JSON as orthographic images.

```sh
LUNE=/opt/tools/l11/lune   # Lune 0.11; 0.10.4 cannot read the place

$LUNE run tools/preview/export_parts.luau Place1.rbxl /tmp/preview/parts.json
python3 tools/preview/render.py /tmp/preview/parts.json --out-dir /tmp/preview
```

Smooth terrain (`Workspace.Terrain` voxels) is not a part: add it with `--terrain`, see
[Terrain](#terrain) below.

Output files in `--out-dir`: `top.png`, `iso.png`, `iso2.png`, `zoom_1.png`, `zoom_2.png`, ...
Each image has an info box (view, part counts), a scale bar and an axis legend.

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
`Accent == true` get the base colour `Colors[Index]` from
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
| `--views LIST` | `top,iso,iso2,zoom` | which images to render |
| `--zoom X,Z,R[,AZ]` | first base slot, radius 40 | zoom target; repeat for `zoom_1.png`, `zoom_2.png`, ... Optional 4th value = azimuth (default 45). Negative values work (`--zoom -57,-57,30`). |
| `--size PX` | 1600 | output width in pixels (height follows the scene, zoom is 4:3) |
| `--ss N` | 2 | supersampling factor (anti-aliasing) |
| `--elevation DEG` | 35 | camera elevation of the 3D views |
| `--frame auto\|all` | `auto` | `auto` frames the play area: ignores Baseplate-sized parts, water and the outermost 1% of part extents (e.g. ocean-floor slabs), but always includes every base. `all` frames everything except Baseplate-sized parts. |
| `--bounds XMIN,ZMIN,XMAX,ZMAX` | | frame this XZ rectangle instead |
| `--zoom-cull F` | 2.0 | zoom views hide parts farther than `radius * F` from the centre so they don't block the view (0 = off) |
| `--no-outlines` | | no dark edge lines |
| `--no-labels` | | no base-slot number markers |
| `--terrain FILE` | | also draw smooth terrain: heightfield `.npz`/`.json` from `terrain_export.py`, or a raw SmoothGrid `.bin` (decoded on the fly). See [Terrain](#terrain). |
| `--terrain-step STUDS` | auto | terrain quad size: 4 = native voxel columns, 8/16/... = averaged. Auto picks the smallest of 4, 8, 16, ... studs whose quads cover >= 5 output pixels (full 1400-stud world at 1600 px: 8; zooms: 4). |

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

