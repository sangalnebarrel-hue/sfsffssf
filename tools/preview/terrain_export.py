#!/usr/bin/env python3
"""Decode Roblox smooth terrain (Terrain.SmoothGrid bytes) into a heightfield.

Pure Python 3 + numpy. Input is the raw SmoothGrid blob, as written by
export_terrain.luau (or `terrain_check --dump DIR`). Output is a heightfield
on the 4x4-stud voxel column grid that render.py --terrain draws:

  python3 tools/preview/terrain_export.py smoothgrid.bin --out terrain.npz [--stats]
  python3 tools/preview/terrain_export.py smoothgrid.bin --out terrain.json
  python3 tools/preview/terrain_export.py smoothgrid.bin --stats          (no output file)
  python3 tools/preview/terrain_export.py smoothgrid.bin --sample X Y Z   (stud position)

--stats prints the same summary lines as `terrain_check` (tools/terrain_check), so
the two independent decoders can be cross-checked with diff (see README.md).

SmoothGrid format (reference: rbx_terrain, github.com/chteau/rbx-native):
  byte 0 = version 1, byte 1 = log2(chunk edge) = 5; an empty grid is just 01 05.
  Then chunks (32^3 voxels of 4^3 studs) until the end, sorted by x, y, z. Each
  starts with its offset from the previous chunk key (the first from 0,0,0): three
  big-endian i32 with their bytes interleaved by significance (x3 y3 z3 x2 y2 z2 ...).
  Then run records until 32768 voxels are filled, x fastest, then z, then y:
  lead byte = material slot (low 6 bits) | 0x40 occupancy byte follows (else Air = 0,
  anything else 255 = full) | 0x80 count byte follows (run = count + 1). A count of
  0 is a one-voxel run followed by one more byte, the voxel's liquid share.
  A non-Air voxel with occupancy byte b is (b + 1) / 256 full.

Heightfield (arrays indexed [iz, ix]; column (ix, iz) covers studs
x = origin_x + 4*ix .. +4, z = origin_z + 4*iz .. +4):
  top       float32  solid surface y: bottom of the highest solid voxel + 4 * its fill
                     fraction (NaN = no solid in the column)
  material  int16    material slot of that highest solid voxel (-1 = none)
  bottom    float32  bottom y of the lowest solid voxel (NaN = none)
  water     float32  water surface y when water lies above the solid surface (or in
                     an empty column), else NaN. Includes the liquid share of a
                     partly filled top voxel.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import sys

import numpy as np

MATERIALS = [
    "Air", "Water", "Grass", "Slate", "Concrete", "Brick", "Sand", "WoodPlanks", "Rock",
    "Glacier", "Snow", "Sandstone", "Mud", "Basalt", "Ground", "CrackedLava", "Asphalt",
    "Cobblestone", "Ice", "LeafyGrass", "Salt", "Limestone", "Pavement",
]  # fmt: skip
WATER = 1
CHUNK = 32
CELLS = CHUNK**3
VOXEL = 4.0
FARTHEST_CHUNK = 32000 // (CHUNK * 4) + 1  # Roblox terrain extent is +-32000 studs
MAX_COLUMNS = 8192  # heightfield size limit per axis (voxel columns)


class SmoothGridError(ValueError):
    pass


# ----------------------------------------------------------------------------------
# Decoder
# ----------------------------------------------------------------------------------


def decode(data: bytes) -> dict:
    """SmoothGrid bytes -> {(cx, cy, cz): (material, occupancy, liquid)}.

    Each array is uint8 with shape (32, 32, 32) indexed [y, z, x] (the stored order
    flattened in C order). Values are normalized like Roblox's reader: Air has
    occupancy 0 and no liquid; only a partly filled solid voxel keeps its liquid
    byte. All-Air chunks are dropped.
    """
    data = bytes(data)
    if len(data) == 0:
        raise SmoothGridError("SmoothGrid is empty, not even a header")
    if data[0] != 1:
        raise SmoothGridError(f"SmoothGrid version {data[0]} is not 1")
    if len(data) < 2 or data[1] != 5:
        raise SmoothGridError("SmoothGrid chunk size is not 2^5")
    chunks = {}
    key = [0, 0, 0]
    pos = 2
    n = len(data)
    while pos < n:
        if pos + 12 > n:
            raise SmoothGridError(f"SmoothGrid ends in the middle of a chunk header (byte {pos})")
        h = data[pos : pos + 12]
        for axis in range(3):
            delta = int.from_bytes(bytes((h[axis], h[3 + axis], h[6 + axis], h[9 + axis])), "big")
            v = (key[axis] + delta) & 0xFFFFFFFF
            key[axis] = v - (1 << 32) if v & 0x80000000 else v
        if any(abs(v) > FARTHEST_CHUNK for v in key):
            raise SmoothGridError(f"SmoothGrid chunk {tuple(key)} is outside the terrain's extent")
        k = tuple(key)
        if k in chunks:
            raise SmoothGridError(f"SmoothGrid repeats chunk {k}")
        pos += 12
        try:
            pos, cells = _decode_chunk(data, pos)
        except IndexError:
            raise SmoothGridError(f"SmoothGrid ends in the middle of chunk {k}") from None
        chunks[k] = cells
    return {k: v for k, v in chunks.items() if v is not None}


def _decode_chunk(data, pos):
    mats, occs, liqs, runs = [], [], [], []
    am, ao, al, ar = mats.append, occs.append, liqs.append, runs.append
    filled = 0
    while filled < CELLS:
        lead = data[pos]
        pos += 1
        slot = lead & 0x3F
        if slot > 22:
            raise SmoothGridError(f"SmoothGrid voxel material slot {slot} is past the 23 terrain materials")
        if lead & 0x40:
            occ = data[pos]
            pos += 1
        else:
            occ = 255
        liq = 0
        run = 1
        if lead & 0x80:
            count = data[pos]
            pos += 1
            if count == 0:
                liq = data[pos]
                pos += 1
            else:
                run = count + 1
        filled += run
        if filled > CELLS:
            raise SmoothGridError("SmoothGrid run overflows its chunk")
        am(slot)
        ao(occ)
        al(liq)
        ar(run)
    mat = np.array(mats, np.uint8)
    if not mat.any():
        return pos, None  # all Air: dropped like Roblox does
    occ = np.array(occs, np.uint8)
    liq = np.array(liqs, np.uint8)
    air = mat == 0
    occ[air] = 0
    liq[(mat <= WATER) | (occ == 255)] = 0
    run = np.array(runs, np.int64)
    shape = (CHUNK, CHUNK, CHUNK)
    return pos, (
        np.repeat(mat, run).reshape(shape),
        np.repeat(occ, run).reshape(shape),
        np.repeat(liq, run).reshape(shape),
    )


def digest(chunks: dict) -> str:
    """SHA-256 matching `terrain_check`'s voxel digest: chunks in (x, y, z) order, each
    as three little-endian i32 then 32768 x (slot, occupancy, liquid)."""
    h = hashlib.sha256()
    for key in sorted(chunks):
        mat, occ, liq = chunks[key]
        h.update(np.array(key, "<i4").tobytes())
        h.update(np.stack([mat.ravel(), occ.ravel(), liq.ravel()], 1).tobytes())
    return h.hexdigest()


def voxel_at(chunks: dict, vx: int, vy: int, vz: int):
    """(slot, occupancy, liquid) of the voxel with integer voxel coordinates."""
    key = (vx // CHUNK, vy // CHUNK, vz // CHUNK)
    if key not in chunks:
        return 0, 0, 0
    mat, occ, liq = chunks[key]
    i = (vy % CHUNK, vz % CHUNK, vx % CHUNK)
    return int(mat[i]), int(occ[i]), int(liq[i])


# ----------------------------------------------------------------------------------
# Heightfield
# ----------------------------------------------------------------------------------


def heightfield(chunks: dict) -> dict:
    """Column surfaces of the decoded chunks (see the module docstring)."""
    if not chunks:
        empty = np.zeros((0, 0), np.float32)
        return {
            "origin": np.array([0.0, 0.0]),
            "step": 4.0,
            "top": empty,
            "bottom": empty.copy(),
            "water": empty.copy(),
            "material": np.zeros((0, 0), np.int16),
            "materials": list(MATERIALS),
        }
    keys = np.array(sorted(chunks))
    cx0, cz0 = int(keys[:, 0].min()), int(keys[:, 2].min())
    cx1, cz1 = int(keys[:, 0].max()), int(keys[:, 2].max())
    nx, nz = (cx1 - cx0 + 1) * CHUNK, (cz1 - cz0 + 1) * CHUNK
    if nx > MAX_COLUMNS or nz > MAX_COLUMNS:
        raise SmoothGridError(f"terrain spans {nx} x {nz} voxel columns, more than {MAX_COLUMNS}")
    top = np.full((nz, nx), np.nan, np.float32)
    bottom = np.full((nz, nx), np.nan, np.float32)
    water = np.full((nz, nx), np.nan, np.float32)
    material = np.full((nz, nx), -1, np.int16)

    columns = {}
    for (cx, cy, cz), cells in chunks.items():
        columns.setdefault((cx, cz), []).append((cy, cells))
    zz, xx = np.indices((CHUNK, CHUNK))
    for (cx, cz), stack in columns.items():
        stack.sort(key=lambda item: item[0])
        mat = np.concatenate([c[0] for _, c in stack])  # (L, 32, 32) [y, z, x]
        occ = np.concatenate([c[1] for _, c in stack])
        liq = np.concatenate([c[2] for _, c in stack])
        ybase = np.concatenate([np.arange(CHUNK) + cy * CHUNK for cy, _ in stack])
        L = mat.shape[0]
        solid = mat > WATER
        has = solid.any(0)
        itop = L - 1 - np.argmax(solid[::-1], axis=0)
        ibot = np.argmax(solid, axis=0)
        occ_top = occ[itop, zz, xx].astype(np.float64)
        ytop = ybase[itop].astype(np.float64)
        t = ytop * VOXEL + VOXEL * (occ_top + 1) / 256
        b = ybase[ibot].astype(np.float64) * VOXEL
        m = mat[itop, zz, xx].astype(np.int16)

        # Water above the solid surface (anywhere in the column when there is none).
        layer = np.arange(L)[:, None, None]
        wet = (mat == WATER) & (layer > np.where(has, itop, -1)[None])
        has_w = wet.any(0)
        iw = L - 1 - np.argmax(wet[::-1], axis=0)
        w = ybase[iw].astype(np.float64) * VOXEL + VOXEL * (occ[iw, zz, xx].astype(np.float64) + 1) / 256
        # Liquid share of a partly filled top voxel (same f32 maths as rbx_terrain).
        liq_top = liq[itop, zz, xx]
        solid_frac = ((occ_top + 1) / 256).astype(np.float32)
        water_frac = np.minimum(liq_top.astype(np.float32) / np.float32(255), np.float32(1) - solid_frac)
        w_share = ytop * VOXEL + VOXEL * np.minimum((solid_frac + water_frac).astype(np.float64), 1.0)
        share = has & ~has_w & (liq_top > 0)
        w = np.where(has_w, w, np.where(share, w_share, np.nan))

        rz = slice((cz - cz0) * CHUNK, (cz - cz0 + 1) * CHUNK)
        rx = slice((cx - cx0) * CHUNK, (cx - cx0 + 1) * CHUNK)
        top[rz, rx] = np.where(has, t, np.nan)
        bottom[rz, rx] = np.where(has, b, np.nan)
        material[rz, rx] = np.where(has, m, -1)
        water[rz, rx] = w

    # Trim empty margins.
    used = np.isfinite(top) | np.isfinite(water)
    rows, cols = np.nonzero(used.any(1))[0], np.nonzero(used.any(0))[0]
    if len(rows) == 0:
        rows = cols = np.array([0])
    rz = slice(rows[0], rows[-1] + 1)
    rx = slice(cols[0], cols[-1] + 1)
    return {
        "origin": np.array([(cx0 * CHUNK + cols[0]) * VOXEL, (cz0 * CHUNK + rows[0]) * VOXEL]),
        "step": 4.0,
        "top": top[rz, rx],
        "bottom": bottom[rz, rx],
        "water": water[rz, rx],
        "material": material[rz, rx],
        "materials": list(MATERIALS),
    }


def save_heightfield(hf: dict, path: str, meta: dict | None = None):
    meta = dict(meta or {})
    if path.endswith(".json"):

        def grid(a, digits=3):
            return [[None if not math.isfinite(v) else round(float(v), digits) for v in row] for row in a]

        doc = {
            "format": "terrain-heightfield-1",
            "origin": [float(v) for v in hf["origin"]],
            "step": float(hf["step"]),
            "size": [int(hf["top"].shape[1]), int(hf["top"].shape[0])],
            "materials": hf["materials"],
            "top": grid(hf["top"]),
            "bottom": grid(hf["bottom"]),
            "water": grid(hf["water"]),
            "material": hf["material"].astype(int).tolist(),
            "meta": meta,
        }
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(doc, fh, separators=(",", ":"))
    else:
        np.savez_compressed(
            path,
            origin=hf["origin"],
            step=np.array(hf["step"]),
            top=hf["top"],
            bottom=hf["bottom"],
            water=hf["water"],
            material=hf["material"],
            materials=np.array(hf["materials"]),
            meta=np.array(json.dumps(meta)),
        )


def load_heightfield(path: str) -> dict:
    """Heightfield from .npz / .json written by this script, or decoded from a raw
    SmoothGrid .bin (anything else)."""
    if path.endswith(".npz"):
        with np.load(path) as z:
            return {
                "origin": z["origin"].astype(float),
                "step": float(z["step"]),
                "top": z["top"].astype(np.float32),
                "bottom": z["bottom"].astype(np.float32),
                "water": z["water"].astype(np.float32),
                "material": z["material"].astype(np.int16),
                "materials": [str(s) for s in z["materials"]],
            }
    if path.endswith(".json"):
        with open(path, "r", encoding="utf-8") as fh:
            doc = json.load(fh)

        def arr(name):
            a = np.array(doc[name], dtype=object)
            return np.where(a == None, np.nan, a).astype(np.float32)  # noqa: E711

        return {
            "origin": np.array(doc["origin"], float),
            "step": float(doc["step"]),
            "top": arr("top").reshape(-1, doc["size"][0]),
            "bottom": arr("bottom").reshape(-1, doc["size"][0]),
            "water": arr("water").reshape(-1, doc["size"][0]),
            "material": np.array(doc["material"], np.int16).reshape(-1, doc["size"][0]),
            "materials": doc["materials"],
        }
    with open(path, "rb") as fh:
        return heightfield(decode(fh.read()))


# ----------------------------------------------------------------------------------
# Statistics (same lines as terrain_check)
# ----------------------------------------------------------------------------------


def stats_lines(data: bytes, chunks: dict, hf: dict) -> list:
    lines = [f"SmoothGrid: {len(data)} bytes, version {data[0]}, chunk log2 {data[1]}"]
    if not chunks:
        return lines + ["chunks: 0 (empty terrain)"]
    keys = np.array(sorted(chunks))

    def rng(a):
        return f"{a.min()}..{a.max()}"

    lines.append(
        f"chunks: {len(chunks)} (chunk x {rng(keys[:, 0])} y {rng(keys[:, 1])} z {rng(keys[:, 2])};"
        " 1 chunk = 32^3 voxels = 128 studs)"
    )
    full = np.zeros(23, np.int64)
    partial = np.zeros(23, np.int64)
    buckets = np.zeros(5, np.int64)
    liquid = 0
    lo = np.array([np.inf] * 3)
    hi = np.array([-np.inf] * 3)
    for (cx, cy, cz), (mat, occ, liq) in chunks.items():
        nonair = mat > 0
        isfull = nonair & (occ == 255)
        full += np.bincount(mat[isfull], minlength=23)
        partial += np.bincount(mat[nonair & ~isfull], minlength=23)
        o = occ[nonair]
        buckets += [
            np.count_nonzero(o == 255),
            np.count_nonzero((o >= 192) & (o < 255)),
            np.count_nonzero((o >= 128) & (o < 192)),
            np.count_nonzero((o >= 64) & (o < 128)),
            np.count_nonzero(o < 64),
        ]
        liquid += int(np.count_nonzero(liq))
        ys, zs, xs = (np.nonzero(nonair.any(axis=a))[0] for a in ((1, 2), (0, 2), (0, 1)))
        if len(xs):
            origin = np.array([cx, cy, cz]) * CHUNK
            lo = np.minimum(lo, origin + [xs[0], ys[0], zs[0]])
            hi = np.maximum(hi, origin + [xs[-1] + 1, ys[-1] + 1, zs[-1] + 1])
    total = int(full.sum() + partial.sum())
    water = int(full[WATER] + partial[WATER])
    lines.append(
        f"voxels: {total} non-Air = {total - water} solid + {water} water;"
        f" {liquid} solid voxels carry a liquid share"
    )
    lo, hi = lo.astype(int) * 4, hi.astype(int) * 4
    size = hi - lo
    lines.append(
        f"voxel bbox (studs): x {lo[0]}..{hi[0]}  y {lo[1]}..{hi[1]}  z {lo[2]}..{hi[2]}"
        f"  (size {size[0]} x {size[1]} x {size[2]})"
    )
    lines.append("materials (voxels: total = full + partial):")
    for slot in range(23):
        t = int(full[slot] + partial[slot])
        if t:
            lines.append(
                f"  {MATERIALS[slot]:<12} {t:>9} = {int(full[slot]):>9} + {int(partial[slot]):>8}"
                f"  ({100.0 * t / total:5.1f}%)"
            )
    pct_full = 100.0 * buckets[0] / max(total, 1)
    lines.append(
        f"occupancy (non-Air): 255 full {buckets[0]} ({pct_full:.1f}%) | 192-254 {buckets[1]} |"
        f" 128-191 {buckets[2]} | 64-127 {buckets[3]} | 0-63 {buckets[4]} ({100.0 - pct_full:.1f}% partial)"
    )

    def summary(a):
        a = a[np.isfinite(a)].astype(np.float64)
        if len(a) == 0:
            return "none"
        return f"{len(a)} columns, y {a.min():.2f}..{a.max():.2f}, mean {a.mean():.2f}"

    lines.append(f"solid surface (4x4-stud columns): {summary(hf['top'])}")
    lines.append(f"water surface (4x4-stud columns): {summary(hf['water'])}")
    lines.append(f"voxel digest (sha256): {digest(chunks)}")
    return lines


def describe(slot, occ, liq):
    if slot == 0:
        return "Air"
    s = f"{MATERIALS[slot]} occupancy {occ} ({(occ + 1) / 256:.3f} full)"
    if liq:
        solid = (occ + 1) / 256 if slot > WATER else 0.0
        s += f", liquid {liq} ({min(liq / 255, 1 - solid):.3f} water)"
    return s


# ----------------------------------------------------------------------------------
# CLI
# ----------------------------------------------------------------------------------


def main(argv=None):
    ap = argparse.ArgumentParser(description="Decode Terrain.SmoothGrid bytes into a heightfield.")
    ap.add_argument("smoothgrid", help="raw SmoothGrid blob (from export_terrain.luau)")
    ap.add_argument("--out", help="heightfield output: .npz (default format) or .json")
    ap.add_argument("--stats", action="store_true", help="print the terrain_check-compatible summary")
    ap.add_argument("--sample", nargs=3, type=float, action="append", default=[], metavar=("X", "Y", "Z"),
                    help="print the voxel at a stud position (repeatable)")  # fmt: skip
    args = ap.parse_args(argv)

    import time

    t0 = time.time()
    with open(args.smoothgrid, "rb") as fh:
        data = fh.read()
    try:
        chunks = decode(data)
    except SmoothGridError as e:
        print(f"terrain_export: decode error: {e}", file=sys.stderr)
        return 2
    t1 = time.time()
    hf = heightfield(chunks)
    t2 = time.time()
    print(
        f"[terrain] {len(data)} bytes -> {len(chunks)} chunks ({t1 - t0:.2f}s) -> heightfield"
        f" {hf['top'].shape[1]} x {hf['top'].shape[0]} columns ({t2 - t1:.2f}s)",
        file=sys.stderr,
    )
    if args.stats:
        print("\n".join(stats_lines(data, chunks, hf)))
    for x, y, z in args.sample:
        v = [math.floor(c / VOXEL) for c in (x, y, z)]
        slot, occ, liq = voxel_at(chunks, *v)
        print(f"stud ({x:g}, {y:g}, {z:g}) -> voxel ({v[0]}, {v[1]}, {v[2]})")
        print(f"voxel: {describe(slot, occ, liq)}")
        print(f"material={MATERIALS[slot]} occupancy={occ} liquid={liq}")
        ox, oz = hf["origin"]
        ix, iz = int((v[0] * VOXEL - ox) // VOXEL), int((v[2] * VOXEL - oz) // VOXEL)
        if 0 <= iz < hf["top"].shape[0] and 0 <= ix < hf["top"].shape[1]:
            t, w, m = hf["top"][iz, ix], hf["water"][iz, ix], hf["material"][iz, ix]
            print(
                f"column: surface y={t:.3f} ({MATERIALS[m] if m >= 0 else 'none'}), "
                f"water y={w:.3f}" if math.isfinite(t) else f"column: no solid, water y={w:.3f}"
            )
    if args.out:
        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        meta = {"source": os.path.abspath(args.smoothgrid), "bytes": len(data), "chunks": len(chunks)}
        save_heightfield(hf, args.out, meta)
        print(f"[terrain] wrote {args.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
