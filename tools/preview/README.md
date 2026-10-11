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
