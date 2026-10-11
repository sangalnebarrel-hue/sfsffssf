//! Roblox smooth terrain: the voxel grid behind `Terrain.SmoothGrid` and the
//! codecs for it and for `PhysicsGrid`.
//!
//! VENDORED, trimmed copy of the `rbx_terrain` crate from
//! <https://github.com/chteau/rbx-native> (master, `crates/rbx_terrain`),
//! MIT licensed (see `LICENSE` next to this file). Upstream verified this
//! codec by re-encoding a real place's `SmoothGrid` byte for byte.
//!
//! `cell.rs`, `material.rs`, `grid.rs`, `smooth_grid.rs` (+ its
//! `smooth_grid/tests.rs`) and `physics_grid.rs` are byte-identical copies of
//! the upstream files. Only this `lib.rs` differs: it drops the modules the
//! codecs do not need (editing, generation, import, meshing, noise, raycast,
//! `MaterialColors`). Do not edit the copied files; re-copy them from
//! upstream instead so they stay comparable.

mod cell;
mod grid;
mod material;
pub mod physics_grid;
pub mod smooth_grid;

pub use cell::{quantize, Cell, FULL};
pub use grid::{Before, ChunkKey, VoxelGrid, Voxels, CHUNK, VOXEL_STUDS};
pub use material::Material;
pub use smooth_grid::SmoothGridError;
