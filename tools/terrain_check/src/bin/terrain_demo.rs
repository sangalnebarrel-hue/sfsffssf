//! terrain_demo: writes test terrain blobs with the reference encoder, for
//! exercising the terrain tooling before a real terrain generator exists.
//!
//! ```text
//! terrain_demo <out_dir>          small test scene (320 x 320 studs)
//! terrain_demo <out_dir> --big    1408 x 1408-stud world (renderer timing)
//! ```
//!
//! Writes `<out_dir>/smoothgrid.bin` and `<out_dir>/physicsgrid.bin`; put
//! them into a place with `tools/terrain_check/inject.luau`.
//!
//! Small scene (all heights in studs, the place's Baseplate top is y = 0):
//! a Grass hill at (40, -30) whose plateau is ringed by a Rock/Slate cliff
//! and topped by a Snow cap (Glacier underneath), a Sand-rimmed pool at
//! (-70, 60) holding Water up to y = 12 (Mud on its floor), a Cobblestone
//! road along z = 100 and a Pavement square at (100, 100). Ground, Rock and
//! Basalt fill the inside down to y = -32. Partly filled voxels under the
//! water carry a liquid share, so every record kind of the format occurs.

use rbx_terrain::{physics_grid, quantize, smooth_grid, Cell, Material, VoxelGrid};

const VS: f32 = 4.0;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let big = args.iter().any(|a| a == "--big");
    let Some(out) = args.iter().find(|a| !a.starts_with("--")) else {
        eprintln!("usage: terrain_demo <out_dir> [--big]");
        std::process::exit(2);
    };
    let grid = if big { big_world() } else { small_scene() };
    let smooth = smooth_grid::encode(&grid);
    let physics = physics_grid::encode(&grid);
    std::fs::create_dir_all(out).expect("create output directory");
    let dir = std::path::Path::new(out);
    std::fs::write(dir.join("smoothgrid.bin"), &smooth).expect("write smoothgrid.bin");
    std::fs::write(dir.join("physicsgrid.bin"), &physics).expect("write physicsgrid.bin");
    let (min, max) = grid.bounds().unwrap_or(([0; 3], [0; 3]));
    println!(
        "terrain_demo: {} chunks, voxel bbox {:?}..{:?}; smoothgrid.bin {} bytes, physicsgrid.bin {} bytes -> {}",
        grid.chunk_count(),
        min,
        max,
        smooth.len(),
        physics.len(),
        dir.display()
    );
}

// ---------------------------------------------------------------------------
// Small helpers: hash noise, smoothstep.
// ---------------------------------------------------------------------------

fn hash(x: i32, z: i32, seed: u32) -> f32 {
    let mut h = (x as u32).wrapping_mul(0x8da6_b343) ^ (z as u32).wrapping_mul(0xd816_3841) ^ seed.wrapping_mul(0xcb1a_b31f);
    h ^= h >> 13;
    h = h.wrapping_mul(0x5bd1_e995);
    h ^= h >> 15;
    (h & 0x00ff_ffff) as f32 / 16_777_216.0
}

fn value_noise(x: f32, z: f32, seed: u32) -> f32 {
    let (x0, z0) = (x.floor(), z.floor());
    let (fx, fz) = (x - x0, z - z0);
    let (sx, sz) = (fx * fx * (3.0 - 2.0 * fx), fz * fz * (3.0 - 2.0 * fz));
    let (ix, iz) = (x0 as i32, z0 as i32);
    let a = hash(ix, iz, seed);
    let b = hash(ix + 1, iz, seed);
    let c = hash(ix, iz + 1, seed);
    let d = hash(ix + 1, iz + 1, seed);
    let top = a + (b - a) * sx;
    let bottom = c + (d - c) * sx;
    (top + (bottom - top) * sz) * 2.0 - 1.0
}

fn fbm(x: f32, z: f32, octaves: u32, seed: u32) -> f32 {
    let (mut sum, mut amp, mut freq, mut norm) = (0.0, 1.0, 1.0, 0.0);
    for o in 0..octaves {
        sum += amp * value_noise(x * freq, z * freq, seed + o * 101);
        norm += amp;
        amp *= 0.5;
        freq *= 2.0;
    }
    sum / norm
}

fn smoothstep(edge0: f32, edge1: f32, x: f32) -> f32 {
    let t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

/// Fills one column: solid up to `top` (materials from `material(depth, y)`,
/// depth in voxels below the surface voxel), water up to `water`.
fn fill_column(
    grid: &mut VoxelGrid,
    x: i32,
    z: i32,
    bottom_voxel: i32,
    top: f32,
    water: Option<f32>,
    material: &dyn Fn(i32, i32) -> Material,
) {
    let level = water.unwrap_or(f32::NEG_INFINITY);
    let top_voxel = ((top.max(level)) / VS).ceil() as i32;
    let surface_voxel = (top / VS).ceil() as i32 - 1;
    for y in bottom_voxel..top_voxel {
        let bottom = y as f32 * VS;
        let fill = ((top - bottom) / VS).clamp(0.0, 1.0);
        let wet = ((level - bottom) / VS).clamp(0.0, 1.0);
        let cell = if fill > 0.0 {
            let mat = material(surface_voxel - y, y);
            let share = wet - fill;
            if fill < 1.0 && share > 0.0 {
                Cell::new(mat, quantize(fill), (share * 255.0).round() as u8)
            } else {
                Cell::with_fraction(mat, fill)
            }
        } else if wet > 0.0 {
            Cell::with_fraction(Material::Water, wet)
        } else {
            continue;
        };
        grid.set([x, y, z], cell);
    }
}

// ---------------------------------------------------------------------------
// Small test scene.
// ---------------------------------------------------------------------------

fn small_scene() -> VoxelGrid {
    const WATER: f32 = 12.0;
    let hill = (40.0f32, -30.0f32);
    let pool = (-70.0f32, 60.0f32);
    let height = |x: f32, z: f32| -> f32 {
        let mut h = 16.0 + 1.5 * fbm(x / 40.0, z / 40.0, 3, 7);
        let d = ((x - hill.0).powi(2) + (z - hill.1).powi(2)).sqrt();
        h += 14.0 * smoothstep(100.0, 52.0, d); // foothill slope
        h += 30.0 * smoothstep(52.0, 47.0, d); // cliff ring
        h += 16.0 * smoothstep(40.0, 0.0, d).powf(1.5); // snow cap
        h += 1.5 * fbm(x / 12.0, z / 12.0, 2, 3) * smoothstep(100.0, 60.0, d);
        let dp = ((x - pool.0).powi(2) + (z - pool.1).powi(2)).sqrt();
        h -= 14.0 * smoothstep(56.0, 10.0, dp);
        // Pavement square, flattened.
        if (x - 100.0).abs() < 12.0 && (z - 100.0).abs() < 12.0 {
            h = 18.0;
        }
        h
    };
    let mut grid = VoxelGrid::new();
    for vz in -40..40 {
        for vx in -40..40 {
            let (x, z) = (vx as f32 * VS + 2.0, vz as f32 * VS + 2.0);
            let h = height(x, z);
            let slope = ((height(x + VS, z) - height(x - VS, z)).abs()
                .max((height(x, z + VS) - height(x, z - VS)).abs()))
                / (2.0 * VS);
            let dp = ((x - pool.0).powi(2) + (z - pool.1).powi(2)).sqrt();
            let speckle = hash(vx, vz, 99);
            let road = (z - 100.0).abs() < 4.0 && x > -20.0 && x < 88.0;
            let square = (x - 100.0).abs() < 12.0 && (z - 100.0).abs() < 12.0;
            let surface = if square {
                Material::Pavement
            } else if road {
                Material::Cobblestone
            } else if slope > 1.2 {
                Material::Rock // replaced by Rock/Slate bands below
            } else if h > 66.0 {
                Material::Snow
            } else if h < 5.0 {
                Material::Mud
            } else if h < WATER + 3.0 && dp < 72.0 {
                Material::Sand
            } else if speckle < 0.15 {
                Material::LeafyGrass
            } else {
                Material::Grass
            };
            let water = (h < WATER).then_some(WATER);
            let material = move |depth: i32, y: i32| -> Material {
                if y < -4 {
                    Material::Basalt
                } else if surface == Material::Rock || depth >= 3 {
                    if (y / 2) % 2 == 0 {
                        Material::Rock
                    } else {
                        Material::Slate
                    }
                } else if depth == 0 {
                    surface
                } else if surface == Material::Snow {
                    Material::Glacier
                } else if surface == Material::Sand || surface == Material::Mud {
                    Material::Sand
                } else {
                    Material::Ground
                }
            };
            fill_column(&mut grid, vx, vz, -8, h, water, &material);
        }
    }
    grid
}

// ---------------------------------------------------------------------------
// Big world (renderer timing): lake + island + terraces + mountain ring,
// laid out like MapConfig (lake r 220, island r 64, mountains r 420..620).
// ---------------------------------------------------------------------------

fn big_world() -> VoxelGrid {
    const WATER: f32 = 0.0;
    let height = |x: f32, z: f32| -> f32 {
        let r = (x * x + z * z).sqrt();
        let n = fbm(x / 90.0, z / 90.0, 4, 11);
        let mut h = if r < 46.0 {
            4.0
        } else if r < 64.0 {
            4.0 - 10.0 * smoothstep(46.0, 64.0, r)
        } else if r < 220.0 {
            -6.0 - 10.0 * smoothstep(64.0, 140.0, r) * smoothstep(220.0, 150.0, r)
        } else if r < 420.0 {
            -6.0 + 12.0 * smoothstep(220.0, 250.0, r) + 8.0 * smoothstep(300.0, 410.0, r) + 3.0 * n
        } else {
            let ridge = 1.0 - fbm(x / 70.0, z / 70.0, 4, 23).abs();
            14.0 + 150.0 * smoothstep(420.0, 520.0, r) * smoothstep(700.0, 600.0, r) * (0.55 + 0.45 * ridge)
                + 6.0 * n
        };
        // Rivers at 45, 225 and 315 degrees (angle from +Z towards +X).
        for deg in [45.0f32, 225.0, 315.0] {
            let a = deg.to_radians();
            let (dx, dz) = (a.sin(), a.cos());
            let along = x * dx + z * dz;
            let across = (x * dz - z * dx).abs();
            if along > 200.0 && along < 640.0 {
                let carve = smoothstep(18.0, 6.0, across);
                h = h * (1.0 - carve) + -5.0 * carve;
            }
        }
        h
    };
    let mut grid = VoxelGrid::new();
    for vz in -176..176 {
        for vx in -176..176 {
            let (x, z) = (vx as f32 * VS + 2.0, vz as f32 * VS + 2.0);
            let h = height(x, z);
            let slope = ((height(x + VS, z) - height(x - VS, z)).abs()
                .max((height(x, z + VS) - height(x, z - VS)).abs()))
                / (2.0 * VS);
            let speckle = hash(vx, vz, 5);
            let surface = if slope > 1.1 {
                Material::Rock
            } else if h > 110.0 {
                Material::Snow
            } else if h > 80.0 {
                Material::Slate
            } else if h < 2.5 {
                Material::Sand
            } else if speckle < 0.2 {
                Material::LeafyGrass
            } else {
                Material::Grass
            };
            let water = (h < WATER).then_some(WATER);
            let material = move |depth: i32, _y: i32| -> Material {
                if depth == 0 {
                    surface
                } else if depth < 3 && surface != Material::Rock {
                    Material::Ground
                } else {
                    Material::Rock
                }
            };
            fill_column(&mut grid, vx, vz, -8, h, water, &material);
        }
    }
    grid
}
