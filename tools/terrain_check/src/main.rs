//! terrain_check: decode, validate and sample Roblox smooth terrain blobs
//! (`Workspace.Terrain.SmoothGrid` / `PhysicsGrid`) with the vendored
//! reference codec in `src/rbx_terrain` (upstream: chteau/rbx-native).
//!
//! ```text
//! terrain_check [options] <place.rbxl>
//! terrain_check [options] --raw <smoothgrid.bin> [<physicsgrid.bin>]
//! terrain_check --sample <place.rbxl> <x> <y> <z>          (stud position)
//! terrain_check --sample --raw <smoothgrid.bin> <x> <y> <z>
//! ```
//!
//! Exit status: 0 = decoded, canonical and PhysicsGrid matches;
//! 1 = decoded but a check failed (non-canonical bytes, PhysicsGrid
//! mismatch or missing); 2 = usage, I/O or decode error.
//!
//! See tools/preview/README.md ("Terrain") for the full workflow.

use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::fmt::Write as _;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use rbx_terrain::{physics_grid, smooth_grid, Cell, ChunkKey, Material, VoxelGrid, CHUNK};
use sha2::{Digest, Sha256};

const USAGE: &str = "\
usage:
  terrain_check [options] <place.rbxl>
  terrain_check [options] --raw <smoothgrid.bin> [<physicsgrid.bin>]
  terrain_check --sample <place.rbxl> <x> <y> <z>
  terrain_check --sample --raw <smoothgrid.bin> <x> <y> <z>

Decodes Workspace.Terrain.SmoothGrid with the reference decoder (rbx_terrain),
prints statistics, re-encodes it and checks the bytes are identical
(canonical), and recomputes PhysicsGrid from the voxels and compares it with
the stored one. --sample prints the voxel at a stud position instead.

options:
  --raw            inputs are raw blob files instead of a place
  --sample         sample mode: last three arguments are stud x y z
  --dump DIR       write the input blobs to DIR/smoothgrid.bin, DIR/physicsgrid.bin
  --emit DIR       write the reference encoding of the decoded voxels to
                   DIR/smoothgrid.canonical.bin and DIR/physicsgrid.canonical.bin
  -q, --quiet      only print the check lines and the result
  -h, --help       this text

exit status: 0 ok, 1 check failed (non-canonical / PhysicsGrid mismatch),
             2 usage, I/O or decode error";

/// Studs per voxel edge (`VOXEL_STUDS` as f64).
const VS: f64 = 4.0;

struct Options {
    raw: bool,
    sample: bool,
    quiet: bool,
    dump: Option<PathBuf>,
    emit: Option<PathBuf>,
    positional: Vec<String>,
}

/// The two blobs and where they came from. `None` = property/file absent.
struct Blobs {
    source: String,
    smooth: Option<Vec<u8>>,
    physics: Option<Vec<u8>>,
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(code) => code,
        Err(message) => {
            eprintln!("terrain_check: error: {message}");
            ExitCode::from(2)
        }
    }
}

fn parse_options(args: &[String]) -> Result<Options, String> {
    let mut opts = Options {
        raw: false,
        sample: false,
        quiet: false,
        dump: None,
        emit: None,
        positional: Vec::new(),
    };
    let mut it = args.iter();
    while let Some(arg) = it.next() {
        match arg.as_str() {
            "-h" | "--help" => {
                println!("{USAGE}");
                std::process::exit(0);
            }
            "--raw" => opts.raw = true,
            "--sample" => opts.sample = true,
            "-q" | "--quiet" => opts.quiet = true,
            "--dump" => opts.dump = Some(it.next().ok_or("--dump needs a directory")?.into()),
            "--emit" => opts.emit = Some(it.next().ok_or("--emit needs a directory")?.into()),
            // Negative coordinates ("-12.5") are positional, not flags.
            s if s.starts_with('-') && s.parse::<f64>().is_err() => {
                return Err(format!("unknown option {s}\n{USAGE}"));
            }
            s => opts.positional.push(s.to_string()),
        }
    }
    Ok(opts)
}

fn run(args: &[String]) -> Result<ExitCode, String> {
    let mut opts = parse_options(args)?;
    let mut point = None;
    if opts.sample {
        if opts.positional.len() < 4 {
            return Err(format!("--sample needs an input and x y z\n{USAGE}"));
        }
        let coords = opts.positional.split_off(opts.positional.len() - 3);
        let mut p = [0.0f64; 3];
        for (axis, text) in coords.iter().enumerate() {
            p[axis] = text
                .parse()
                .map_err(|_| format!("bad coordinate {text:?}"))?;
        }
        point = Some(p);
    }
    let blobs = load(&opts)?;
    if let Some(dir) = &opts.dump {
        dump_inputs(dir, &blobs)?;
    }
    let smooth = match &blobs.smooth {
        Some(bytes) => bytes.clone(),
        None => vec![1, 5],
    };
    let grid = match smooth_grid::decode(&smooth) {
        Ok(grid) => grid,
        Err(error) => {
            println!("source: {}", blobs.source);
            println!("SmoothGrid: {} bytes", smooth.len());
            println!("decode: FAILED: {error}");
            print_decode_context(&smooth);
            println!("RESULT: DECODE ERROR");
            return Ok(ExitCode::from(2));
        }
    };
    if let Some(p) = point {
        sample(&blobs, &grid, p);
        return Ok(ExitCode::SUCCESS);
    }
    if let Some(dir) = &opts.emit {
        emit_canonical(dir, &grid)?;
    }
    Ok(check(&blobs, &smooth, &grid, opts.quiet))
}

// ---------------------------------------------------------------------------
// Input
// ---------------------------------------------------------------------------

fn load(opts: &Options) -> Result<Blobs, String> {
    if opts.raw {
        let files = &opts.positional;
        if files.is_empty() || files.len() > 2 {
            return Err(format!("--raw takes <smoothgrid.bin> [<physicsgrid.bin>]\n{USAGE}"));
        }
        let read = |path: &str| std::fs::read(path).map_err(|e| format!("cannot read {path}: {e}"));
        let smooth = read(&files[0])?;
        let physics = files.get(1).map(|p| read(p)).transpose()?;
        let source = match files.get(1) {
            Some(p) => format!("raw {} + {}", files[0], p),
            None => format!("raw {}", files[0]),
        };
        return Ok(Blobs {
            source,
            smooth: Some(smooth),
            physics,
        });
    }
    if opts.positional.len() != 1 {
        return Err(format!("expected one place file\n{USAGE}"));
    }
    load_place(Path::new(&opts.positional[0]))
}

fn load_place(path: &Path) -> Result<Blobs, String> {
    let file = std::fs::File::open(path).map_err(|e| format!("cannot open {}: {e}", path.display()))?;
    let dom = rbx_binary::from_reader(std::io::BufReader::new(file))
        .map_err(|e| format!("cannot read {} as a binary place: {e}", path.display()))?;
    let root = dom.root();
    let workspace = root
        .children()
        .iter()
        .filter_map(|r| dom.get_by_ref(*r))
        .find(|i| i.class.as_str() == "Workspace")
        .ok_or("the place has no Workspace")?;
    let terrain = workspace
        .children()
        .iter()
        .filter_map(|r| dom.get_by_ref(*r))
        .find(|i| i.class.as_str() == "Terrain")
        .ok_or("Workspace has no Terrain")?;
    let blob = |name: &str| -> Result<Option<Vec<u8>>, String> {
        use rbx_dom_weak::types::Variant;
        let key = rbx_dom_weak::ustr(name);
        match terrain.properties.get(&key) {
            None => Ok(None),
            Some(Variant::BinaryString(b)) => Ok(Some(AsRef::<[u8]>::as_ref(b).to_vec())),
            Some(Variant::String(s)) => Ok(Some(s.as_bytes().to_vec())),
            Some(Variant::SharedString(s)) => Ok(Some(s.data().to_vec())),
            Some(other) => Err(format!("Terrain.{name} has unexpected type {:?}", other.ty())),
        }
    };
    Ok(Blobs {
        source: format!("{} (Workspace.Terrain)", path.display()),
        smooth: blob("SmoothGrid")?,
        physics: blob("PhysicsGrid")?,
    })
}

fn dump_inputs(dir: &Path, blobs: &Blobs) -> Result<(), String> {
    std::fs::create_dir_all(dir).map_err(|e| format!("cannot create {}: {e}", dir.display()))?;
    for (name, blob) in [("smoothgrid.bin", &blobs.smooth), ("physicsgrid.bin", &blobs.physics)] {
        if let Some(bytes) = blob {
            let path = dir.join(name);
            std::fs::write(&path, bytes).map_err(|e| format!("cannot write {}: {e}", path.display()))?;
            eprintln!("wrote {} ({} bytes)", path.display(), bytes.len());
        }
    }
    Ok(())
}

fn emit_canonical(dir: &Path, grid: &VoxelGrid) -> Result<(), String> {
    std::fs::create_dir_all(dir).map_err(|e| format!("cannot create {}: {e}", dir.display()))?;
    for (name, bytes) in [
        ("smoothgrid.canonical.bin", smooth_grid::encode(grid)),
        ("physicsgrid.canonical.bin", physics_grid::encode(grid)),
    ] {
        let path = dir.join(name);
        std::fs::write(&path, &bytes).map_err(|e| format!("cannot write {}: {e}", path.display()))?;
        eprintln!("wrote {} ({} bytes)", path.display(), bytes.len());
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Statistics
// ---------------------------------------------------------------------------

#[derive(Default)]
struct Stats {
    voxels: u64,
    solid: u64,
    water: u64,
    with_liquid: u64,
    /// Per material slot: (full, partial).
    per_material: [(u64, u64); 23],
    /// Non-Air occupancy byte buckets: 255, 192-254, 128-191, 64-127, 0-63.
    occupancy: [u64; 5],
    bounds: Option<([i32; 3], [i32; 3])>,
}

/// Per (x, z) voxel column: the highest solid voxel and the highest water.
#[derive(Clone, Copy)]
struct Column {
    solid_y: i32,
    solid: Cell,
    water_y: i32,
    water: Cell,
}

fn stats(grid: &VoxelGrid) -> (Stats, HashMap<(i32, i32), Column>) {
    let mut s = Stats::default();
    let mut columns: HashMap<(i32, i32), Column> = HashMap::new();
    for (v, cell) in grid.voxels() {
        s.voxels += 1;
        let slot = usize::from(cell.material.slot());
        let full = cell.occupancy == rbx_terrain::FULL;
        if full {
            s.per_material[slot].0 += 1;
        } else {
            s.per_material[slot].1 += 1;
        }
        s.occupancy[match cell.occupancy {
            255 => 0,
            192..=254 => 1,
            128..=191 => 2,
            64..=127 => 3,
            _ => 4,
        }] += 1;
        if cell.material == Material::Water {
            s.water += 1;
        } else {
            s.solid += 1;
        }
        if cell.liquid != 0 {
            s.with_liquid += 1;
        }
        let (min, max) = s.bounds.get_or_insert((v, v.map(|a| a + 1)));
        for a in 0..3 {
            min[a] = min[a].min(v[a]);
            max[a] = max[a].max(v[a] + 1);
        }
        let col = columns.entry((v[0], v[2])).or_insert(Column {
            solid_y: i32::MIN,
            solid: Cell::AIR,
            water_y: i32::MIN,
            water: Cell::AIR,
        });
        if cell.material.is_solid() {
            if v[1] > col.solid_y {
                col.solid_y = v[1];
                col.solid = cell;
            }
        } else if v[1] > col.water_y {
            col.water_y = v[1];
            col.water = cell;
        }
    }
    (s, columns)
}

/// Stud height of the solid surface in a column whose top solid voxel is
/// `cell` at voxel height `y` (the voxel's fill measured from its bottom).
fn surface(y: i32, cell: Cell) -> f64 {
    f64::from(y) * VS + VS * f64::from(cell.fraction())
}

/// Water surface of a column, if water lies above (or shares) its top solid
/// voxel.
fn water_surface(col: &Column) -> Option<f64> {
    if col.water_y != i32::MIN && col.water_y >= col.solid_y {
        Some(surface(col.water_y, col.water))
    } else if col.solid_y != i32::MIN && col.solid.liquid != 0 {
        let fill = f64::from(col.solid.solid_fraction() + col.solid.water_fraction());
        Some(f64::from(col.solid_y) * VS + VS * fill.min(1.0))
    } else {
        None
    }
}

/// SHA-256 over every stored chunk in key order (x, then y, then z): the key
/// as three little-endian i32, then each of its 32768 voxels as
/// (material slot, occupancy, liquid). tools/preview/terrain_export.py
/// --digest computes the same value from its own decoder.
fn digest(grid: &VoxelGrid) -> String {
    let mut hasher = Sha256::new();
    let mut buf = Vec::with_capacity(3 * (CHUNK * CHUNK * CHUNK) as usize);
    for key in grid.chunk_keys() {
        let Some(cells) = grid.chunk(key) else { continue };
        hasher.update(key.x.to_le_bytes());
        hasher.update(key.y.to_le_bytes());
        hasher.update(key.z.to_le_bytes());
        buf.clear();
        for cell in cells {
            buf.extend([cell.material.slot(), cell.occupancy, cell.liquid]);
        }
        hasher.update(&buf);
    }
    hasher
        .finalize()
        .iter()
        .fold(String::new(), |mut s, b| {
            let _ = write!(s, "{b:02x}");
            s
        })
}

fn print_stats(smooth: &[u8], grid: &VoxelGrid) {
    let (s, columns) = stats(grid);
    println!(
        "SmoothGrid: {} bytes, version {}, chunk log2 {}",
        smooth.len(),
        smooth[0],
        smooth[1]
    );
    let keys: Vec<ChunkKey> = grid.chunk_keys().collect();
    if keys.is_empty() {
        println!("chunks: 0 (empty terrain)");
        return;
    }
    let range = |f: fn(&ChunkKey) -> i32| {
        let lo = keys.iter().map(f).min().unwrap();
        let hi = keys.iter().map(f).max().unwrap();
        format!("{lo}..{hi}")
    };
    println!(
        "chunks: {} (chunk x {} y {} z {}; 1 chunk = 32^3 voxels = 128 studs)",
        keys.len(),
        range(|k| k.x),
        range(|k| k.y),
        range(|k| k.z)
    );
    println!(
        "voxels: {} non-Air = {} solid + {} water; {} solid voxels carry a liquid share",
        s.voxels, s.solid, s.water, s.with_liquid
    );
    if let Some((min, max)) = s.bounds {
        println!(
            "voxel bbox (studs): x {}..{}  y {}..{}  z {}..{}  (size {} x {} x {})",
            min[0] * 4,
            max[0] * 4,
            min[1] * 4,
            max[1] * 4,
            min[2] * 4,
            max[2] * 4,
            (max[0] - min[0]) * 4,
            (max[1] - min[1]) * 4,
            (max[2] - min[2]) * 4
        );
    }
    println!("materials (voxels: total = full + partial):");
    for (slot, (full, partial)) in s.per_material.iter().enumerate() {
        if full + partial == 0 {
            continue;
        }
        let name = Material::from_slot(slot as u8).unwrap().name();
        println!(
            "  {:<12} {:>9} = {:>9} + {:>8}  ({:5.1}%)",
            name,
            full + partial,
            full,
            partial,
            100.0 * (full + partial) as f64 / s.voxels as f64
        );
    }
    let pct = |n: u64| 100.0 * n as f64 / s.voxels.max(1) as f64;
    println!(
        "occupancy (non-Air): 255 full {} ({:.1}%) | 192-254 {} | 128-191 {} | 64-127 {} | 0-63 {} ({:.1}% partial)",
        s.occupancy[0],
        pct(s.occupancy[0]),
        s.occupancy[1],
        s.occupancy[2],
        s.occupancy[3],
        s.occupancy[4],
        100.0 - pct(s.occupancy[0])
    );
    let mut tops: Vec<f64> = Vec::new();
    let mut waters: Vec<f64> = Vec::new();
    for col in columns.values() {
        if col.solid_y != i32::MIN {
            tops.push(surface(col.solid_y, col.solid));
        }
        if let Some(w) = water_surface(col) {
            waters.push(w);
        }
    }
    let summary = |v: &[f64]| -> String {
        if v.is_empty() {
            return "none".into();
        }
        let lo = v.iter().copied().fold(f64::INFINITY, f64::min);
        let hi = v.iter().copied().fold(f64::NEG_INFINITY, f64::max);
        let mean = v.iter().sum::<f64>() / v.len() as f64;
        format!("{} columns, y {:.2}..{:.2}, mean {:.2}", v.len(), lo, hi, mean)
    };
    println!("solid surface (4x4-stud columns): {}", summary(&tops));
    println!("water surface (4x4-stud columns): {}", summary(&waters));
    println!("voxel digest (sha256): {}", digest(grid));
}

// ---------------------------------------------------------------------------
// Checks
// ---------------------------------------------------------------------------

fn check(blobs: &Blobs, smooth: &[u8], grid: &VoxelGrid, quiet: bool) -> ExitCode {
    let mut ok = true;
    println!("source: {}", blobs.source);
    if blobs.smooth.is_none() {
        println!("note: Terrain has no SmoothGrid property; treated as empty (01 05)");
    }
    if !quiet {
        print_stats(smooth, grid);
    }

    // 1. Canonical encoding.
    let encoded = smooth_grid::encode(grid);
    if encoded == smooth {
        println!("canonical: OK (reference re-encode is byte-identical, {} bytes)", smooth.len());
    } else {
        ok = false;
        println!(
            "canonical: MISMATCH (input {} bytes, reference re-encode {} bytes)",
            smooth.len(),
            encoded.len()
        );
        explain_smooth_diff(smooth, &encoded, grid);
    }

    // 2. PhysicsGrid.
    let expected = physics_grid::encode(grid);
    match &blobs.physics {
        None => {
            ok = false;
            println!(
                "PhysicsGrid: MISSING (expected {} bytes, {} regions); write the reference \
                 PhysicsGrid (terrain_check --emit DIR)",
                expected.len(),
                parse_physics(&expected).map_or(0, |p| p.lists[0].len())
            );
        }
        Some(stored) if *stored == expected => {
            let regions = parse_physics(stored).map_or(0, |p| p.lists[0].len());
            println!(
                "PhysicsGrid: OK (stored {} bytes, {} regions, identical to the recomputed one)",
                stored.len(),
                regions
            );
        }
        Some(stored) => {
            ok = false;
            println!(
                "PhysicsGrid: MISMATCH (stored {} bytes, recomputed {} bytes)",
                stored.len(),
                expected.len()
            );
            explain_physics_diff(stored, &expected);
        }
    }

    if ok {
        println!("RESULT: OK");
        ExitCode::SUCCESS
    } else {
        println!("RESULT: FAILED");
        ExitCode::from(1)
    }
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect::<Vec<_>>().join(" ")
}

fn print_decode_context(bytes: &[u8]) {
    // Index as far as it gets, to show which chunk broke.
    let mut at = 2usize;
    let mut chunks = 0;
    if bytes.len() >= 2 {
        while at + 12 <= bytes.len() {
            let mut walker = RecordWalker::new(bytes, at + 12);
            match walker.walk_chunk(&mut |_| {}) {
                Ok(end) => {
                    chunks += 1;
                    at = end;
                }
                Err(e) => {
                    println!(
                        "  {} chunk(s) parsed; chunk #{} (header at byte {}) fails: {} at byte {}",
                        chunks,
                        chunks + 1,
                        at,
                        e,
                        walker.at
                    );
                    let lo = walker.at.saturating_sub(12);
                    let hi = (walker.at + 12).min(bytes.len());
                    println!("  bytes {}..{}: {}", lo, hi, hex(&bytes[lo..hi]));
                    return;
                }
            }
        }
        if at != bytes.len() {
            println!(
                "  {} chunk(s) parsed; {} trailing byte(s) at {} are too short for a chunk header",
                chunks,
                bytes.len() - at,
                at
            );
        }
    }
}

/// One run record as stored, for lint diagnostics.
#[derive(Clone, Copy, Debug)]
struct Record {
    offset: usize,
    lead: u8,
    occupancy: Option<u8>,
    count: Option<u8>,
    liquid: Option<u8>,
    /// Voxel index (inside the chunk) of the first voxel of the run.
    start: usize,
    run: usize,
}

struct RecordWalker<'a> {
    bytes: &'a [u8],
    at: usize,
}

impl<'a> RecordWalker<'a> {
    fn new(bytes: &'a [u8], at: usize) -> Self {
        RecordWalker { bytes, at }
    }

    fn byte(&mut self) -> Result<u8, String> {
        let b = *self.bytes.get(self.at).ok_or("truncated")?;
        self.at += 1;
        Ok(b)
    }

    /// Walks one chunk's records starting at `self.at`; returns the end offset.
    fn walk_chunk(&mut self, visit: &mut dyn FnMut(Record)) -> Result<usize, String> {
        let total = (CHUNK * CHUNK * CHUNK) as usize;
        let mut filled = 0usize;
        while filled < total {
            let offset = self.at;
            let lead = self.byte()?;
            if usize::from(lead & 0x3f) >= 23 {
                return Err(format!("material slot {} > 22", lead & 0x3f));
            }
            let occupancy = if lead & 0x40 != 0 { Some(self.byte()?) } else { None };
            let (count, liquid, run) = if lead & 0x80 != 0 {
                match self.byte()? {
                    0 => (Some(0), Some(self.byte()?), 1),
                    c => (Some(c), None, usize::from(c) + 1),
                }
            } else {
                (None, None, 1)
            };
            if filled + run > total {
                return Err("run overflows the chunk".into());
            }
            visit(Record {
                offset,
                lead,
                occupancy,
                count,
                liquid,
                start: filled,
                run,
            });
            filled += run;
        }
        Ok(self.at)
    }
}

fn local_voxel(index: usize) -> [usize; 3] {
    let e = CHUNK as usize;
    [index % e, index / (e * e), index / e % e]
}

/// Voxel (global, voxels) of a chunk-local index.
fn global_voxel(key: ChunkKey, index: usize) -> [i32; 3] {
    let l = local_voxel(index);
    let o = key.origin();
    [o[0] + l[0] as i32, o[1] + l[1] as i32, o[2] + l[2] as i32]
}

/// Explains why `input` is not what the reference encoder writes: where the
/// first difference is, and which non-canonical patterns the input uses.
fn explain_smooth_diff(input: &[u8], encoded: &[u8], grid: &VoxelGrid) {
    let first = input
        .iter()
        .zip(encoded)
        .position(|(a, b)| a != b)
        .unwrap_or(input.len().min(encoded.len()));
    let index_in = smooth_grid::index(input).unwrap_or_default();
    let index_out = smooth_grid::index(encoded).unwrap_or_default();
    let chunk_at = |index: &smooth_grid::Index, offset: usize| {
        index
            .iter()
            .find(|(_, r)| offset < r.end)
            .map(|(k, r)| (*k, r.clone()))
    };
    print!("  first difference at byte {first}");
    match chunk_at(&index_in, first) {
        Some((key, range)) if first >= range.start => println!(
            " (run records of input chunk ({}, {}, {}), bytes {}..{})",
            key.x, key.y, key.z, range.start, range.end
        ),
        Some((key, range)) => println!(
            " (header of input chunk ({}, {}, {}), whose records start at byte {})",
            key.x, key.y, key.z, range.start
        ),
        None => println!(),
    }
    let lo = first.saturating_sub(8);
    println!("  input   [{lo}..]: {}", hex(&input[lo..(first + 16).min(input.len())]));
    println!("  encoded [{lo}..]: {}", hex(&encoded[lo..(first + 16).min(encoded.len())]));

    // Chunk-level comparison.
    let keys_in: Vec<ChunkKey> = index_in.iter().map(|(k, _)| *k).collect();
    let keys_out: Vec<ChunkKey> = index_out.iter().map(|(k, _)| *k).collect();
    let mut sorted = keys_in.clone();
    sorted.sort();
    if sorted != keys_in {
        println!("  chunks are not in (x, y, z) order: Roblox writes them sorted by x, then y, then z");
    }
    let stored: BTreeSet<ChunkKey> = keys_in.iter().copied().collect();
    let kept: BTreeSet<ChunkKey> = keys_out.iter().copied().collect();
    let dropped: Vec<&ChunkKey> = stored.difference(&kept).collect();
    if !dropped.is_empty() {
        println!(
            "  {} stored chunk(s) are all Air and must be omitted, e.g. {:?}",
            dropped.len(),
            dropped.iter().take(4).map(|k| (k.x, k.y, k.z)).collect::<Vec<_>>()
        );
    }
    let body_out: HashMap<ChunkKey, &[u8]> = index_out
        .iter()
        .map(|(k, r)| (*k, &encoded[r.clone()]))
        .collect();
    let differing: Vec<ChunkKey> = index_in
        .iter()
        .filter(|(k, r)| body_out.get(k).is_some_and(|b| *b != &input[r.clone()]))
        .map(|(k, _)| *k)
        .collect();
    println!(
        "  chunks whose run records differ: {} of {}{}",
        differing.len(),
        index_in.len(),
        if differing.is_empty() {
            String::new()
        } else {
            format!(
                ", e.g. {:?}",
                differing.iter().take(4).map(|k| (k.x, k.y, k.z)).collect::<Vec<_>>()
            )
        }
    );

    // Record-level lint: patterns the reference encoder never writes.
    let mut issues: BTreeMap<&'static str, (u64, String)> = BTreeMap::new();
    let mut note = |what: &'static str, key: ChunkKey, rec: &Record| {
        let entry = issues.entry(what).or_insert((0, String::new()));
        entry.0 += 1;
        if entry.1.is_empty() {
            let v = global_voxel(key, rec.start);
            entry.1 = format!(
                "first at byte {} (voxel {:?} = studs {:?}): record {}",
                rec.offset,
                v,
                v.map(|a| a * 4),
                hex(&input[rec.offset..rec.offset + 1 + rec.occupancy.is_some() as usize
                    + rec.count.is_some() as usize
                    + rec.liquid.is_some() as usize])
            );
        }
    };
    for (key, range) in &index_in {
        let mut records: Vec<Record> = Vec::new();
        let mut walker = RecordWalker::new(input, range.start);
        if walker.walk_chunk(&mut |r| records.push(r)).is_err() {
            continue;
        }
        let cell_of = |r: &Record| {
            let material = Material::from_slot(r.lead & 0x3f).unwrap();
            let occ = r.occupancy.unwrap_or(rbx_terrain::FULL);
            Cell::new(material, occ, r.liquid.unwrap_or(0))
        };
        for (i, rec) in records.iter().enumerate() {
            let slot = rec.lead & 0x3f;
            if slot == 0 && rec.occupancy.is_some_and(|o| o != 0) {
                note("Air record with a nonzero occupancy byte (Air is always 0)", *key, rec);
            } else if slot != 0 && rec.occupancy == Some(255) {
                note("occupancy byte 255 written explicitly (omit it: no 0x40 flag means full)", *key, rec);
            } else if slot == 0 && rec.occupancy == Some(0) {
                note("Air record with an explicit occupancy byte 0 (omit the 0x40 flag)", *key, rec);
            }
            if rec.count == Some(0) {
                let cell = cell_of(rec);
                if rec.liquid == Some(0) {
                    note("count-0 record with liquid byte 0 (write a plain 1-voxel record)", *key, rec);
                } else if cell.liquid == 0 {
                    note(
                        "liquid byte on a voxel that cannot hold one (Air, Water or full solid); \
                         the reader drops it",
                        *key,
                        rec,
                    );
                }
            }
            if let Some(next) = records.get(i + 1) {
                let (a, b) = (cell_of(rec), cell_of(next));
                if a == b && a.liquid == 0 && rec.run < 256 {
                    note(
                        "run split although the next record holds the same voxel (runs must be \
                         greedy, up to 256)",
                        *key,
                        rec,
                    );
                }
            }
        }
    }
    if issues.is_empty() {
        println!("  no record-level problems found (difference is in chunk order/headers or lengths)");
    } else {
        println!("  non-canonical patterns in the input:");
        for (what, (count, example)) in &issues {
            println!("    {count} x {what}\n        {example}");
        }
    }
    match smooth_grid::decode(encoded) {
        Ok(back) if back == *grid => println!(
            "  the voxels themselves round-trip: the input decodes to the same grid the reference \
             bytes do, only the byte layout differs"
        ),
        _ => println!("  INTERNAL: the reference re-encode does not decode to the same voxels"),
    }
}

struct Physics {
    version: u8,
    log2: u8,
    lists: [Vec<[i32; 3]>; 3],
    trailing: usize,
}

fn parse_physics(bytes: &[u8]) -> Result<Physics, String> {
    if bytes.len() < 2 {
        return Err("shorter than its 2-byte header".into());
    }
    let mut at = 2usize;
    let mut lists: [Vec<[i32; 3]>; 3] = Default::default();
    for (n, list) in lists.iter_mut().enumerate() {
        let count = bytes
            .get(at..at + 4)
            .ok_or(format!("list {} count truncated at byte {at}", n + 1))?;
        let count = u32::from_be_bytes(count.try_into().unwrap()) as usize;
        at += 4;
        let mut prev = [0i32; 3];
        for i in 0..count {
            let rec = bytes
                .get(at..at + 12)
                .ok_or(format!("list {} entry {i} of {count} truncated at byte {at}", n + 1))?;
            let mut delta = [0u32; 3];
            for b in 0..4 {
                for axis in 0..3 {
                    delta[axis] = (delta[axis] << 8) | u32::from(rec[b * 3 + axis]);
                }
            }
            for axis in 0..3 {
                prev[axis] = prev[axis].wrapping_add(delta[axis] as i32);
            }
            list.push(prev);
            at += 12;
        }
    }
    Ok(Physics {
        version: bytes[0],
        log2: bytes[1],
        lists,
        trailing: bytes.len() - at,
    })
}

fn explain_physics_diff(stored: &[u8], expected: &[u8]) {
    let want = parse_physics(expected).expect("reference PhysicsGrid parses");
    let got = match parse_physics(stored) {
        Ok(p) => p,
        Err(e) => {
            println!("  stored PhysicsGrid does not parse: {e}");
            println!("  stored head: {}", hex(&stored[..stored.len().min(32)]));
            return;
        }
    };
    if got.version != want.version || got.log2 != want.log2 {
        println!(
            "  header: stored {:02x} {:02x}, expected {:02x} {:02x}",
            got.version, got.log2, want.version, want.log2
        );
    }
    println!(
        "  region lists: stored {} / {} / {}, expected {} / {} / {}",
        got.lists[0].len(),
        got.lists[1].len(),
        got.lists[2].len(),
        want.lists[0].len(),
        want.lists[1].len(),
        want.lists[2].len()
    );
    if got.trailing != 0 {
        println!("  {} trailing byte(s) after the three lists", got.trailing);
    }
    let mut sorted = got.lists[0].clone();
    sorted.sort_by_key(|r| (r[0], r[1], r[2]));
    if sorted != got.lists[0] {
        println!("  stored list 1 is not sorted by x, then y, then z");
    }
    let a: BTreeSet<[i32; 3]> = got.lists[0].iter().copied().collect();
    let b: BTreeSet<[i32; 3]> = want.lists[0].iter().copied().collect();
    if a.len() != got.lists[0].len() {
        println!("  stored list 1 repeats regions");
    }
    let extra: Vec<_> = a.difference(&b).take(6).collect();
    let missing: Vec<_> = b.difference(&a).take(6).collect();
    println!(
        "  regions (8x8x8 voxels) only in stored: {}{}; missing from stored: {}{}",
        a.difference(&b).count(),
        if extra.is_empty() { String::new() } else { format!(" e.g. {extra:?}") },
        b.difference(&a).count(),
        if missing.is_empty() { String::new() } else { format!(" e.g. {missing:?}") }
    );
}

// ---------------------------------------------------------------------------
// Sampling
// ---------------------------------------------------------------------------

fn describe(cell: Cell) -> String {
    if cell.is_air() {
        return "Air".into();
    }
    let mut s = format!(
        "{} occupancy {} ({:.3} full)",
        cell.material.name(),
        cell.occupancy,
        cell.fraction()
    );
    if cell.liquid != 0 {
        let _ = write!(s, ", liquid {} ({:.3} water)", cell.liquid, cell.water_fraction());
    }
    s
}

fn sample(blobs: &Blobs, grid: &VoxelGrid, p: [f64; 3]) {
    let v = p.map(|c| (c / VS).floor() as i32);
    let key = ChunkKey::containing(v);
    let cell = grid.get(v);
    println!("source: {}", blobs.source);
    println!(
        "stud ({}, {}, {}) -> voxel ({}, {}, {}) [studs {}..{}, {}..{}, {}..{}] in chunk ({}, {}, {})",
        p[0],
        p[1],
        p[2],
        v[0],
        v[1],
        v[2],
        v[0] * 4,
        v[0] * 4 + 4,
        v[1] * 4,
        v[1] * 4 + 4,
        v[2] * 4,
        v[2] * 4 + 4,
        key.x,
        key.y,
        key.z
    );
    println!("voxel: {}", describe(cell));
    println!("material={} occupancy={} liquid={}", cell.material.name(), cell.occupancy, cell.liquid);
    // The column through the point.
    let mut col = Column {
        solid_y: i32::MIN,
        solid: Cell::AIR,
        water_y: i32::MIN,
        water: Cell::AIR,
    };
    let (lo, hi) = grid
        .chunk_bounds()
        .map_or((0, 0), |(min, max)| (min[1], max[1]));
    for y in lo..hi {
        let c = grid.get([v[0], y, v[2]]);
        if c.material.is_solid() {
            col.solid_y = y;
            col.solid = c;
        } else if c.material == Material::Water {
            col.water_y = y;
            col.water = c;
        }
    }
    if col.solid_y == i32::MIN {
        println!("column: no solid voxel");
    } else {
        println!(
            "column: top solid voxel y={} ({}) -> surface y={:.3}",
            col.solid_y,
            describe(col.solid),
            surface(col.solid_y, col.solid)
        );
    }
    match water_surface(&col) {
        Some(w) => println!("column: water surface y={w:.3}"),
        None => println!("column: no water above the surface"),
    }
    println!("neighbourhood (voxel y: cell):");
    for y in (v[1] - 2..=v[1] + 2).rev() {
        println!(
            "  {:>4}{} {}",
            y,
            if y == v[1] { "*" } else { " " },
            describe(grid.get([v[0], y, v[2]]))
        );
    }
}
