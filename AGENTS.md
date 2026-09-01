# AGENTS.md

Instructions for coding agents working in this repository.

## What this project is

A 2D physics game in Rust using Rapier, rendered with SDL2, running on a Raspberry Pi 3
Model B+ and displayed on a CRT over composite video.

## Hard constraints

Do not violate these. They come from the hardware, not from taste.

1. **The Pi is the only build target.** There is no desktop build, no cross-compilation, and
   no `cfg` branching for other platforms. Code is edited on a Mac and compiled on the Pi.
   Do not add a windowed preview mode.
2. **SDL2 with the KMSDRM backend.** No winit, no Bevy, no macroquad, no wgpu. Those require
   X11 or Wayland; there is no display server on this device.
3. **Render at 320x240 internally.** Use `Canvas::set_logical_size(320, 240)` and let SDL
   upscale to the 720x480 composite framebuffer. Set `SDL_HINT_RENDER_SCALE_QUALITY` to `0`
   (nearest neighbour).
4. **Fixed timestep of 1/60s.** Accumulate wall-clock time and step Rapier in fixed
   increments. Never pass a variable frame delta to `PhysicsPipeline::step`.
5. **Title-safe inset of 10%.** Nothing the player needs to read may be drawn outside
   x ∈ [32, 288] or y ∈ [24, 216] in logical coordinates. Define these as constants.
6. **No 1px horizontal features.** Interlacing strobes them. Minimum height 2px for any
   horizontal line, border, or text stroke.
7. **Muted palette.** Keep saturation low, especially in reds. Define the palette as a
   single named constant table; do not scatter RGB literals through drawing code.

## Performance budget

VideoCore IV, four A53 cores at 1.4GHz, 1GB RAM shared with the GPU. Per frame at 60Hz you
have ~16ms for physics plus rendering.

- Keep the rigid body count in the low hundreds.
- Prefer the SDL software renderer or simple `fill_rect` / `draw_line` primitives. Do not
  reach for GLES shaders.
- No per-frame heap allocation in the game loop.
- Do not add async runtimes, ECS frameworks, or asset pipelines. This is a single-threaded
  loop with a fixed set of dependencies.

## Dependencies

Add crates with `cargo add` so versions resolve against the current registry. Do not pin
versions from memory — they will be wrong.

Permitted: `rapier2d`, `nalgebra` (re-exported by Rapier), `sdl2`. Adding anything else
requires an explicit reason in the commit message.

Configure `sdl2` to link against the system library. Do **not** enable the `bundled`
feature; compiling SDL from source on a 3B+ takes hours.

## Commands

| Task | Command |
|---|---|
| Sync to Pi | `./scripts/sync.sh` |
| Build and run on Pi | `./scripts/run.sh` |
| Build only (on Pi) | `cargo build -j2` |

All builds happen on the Pi. Never run `cargo build` on the Mac; it will fail on the SDL2
link step and the resulting artifacts are useless.

## Code style

- Rust 2021, `rustfmt` defaults.
- Modules split by responsibility: `physics`, `render`, `input`, `game`. Keep `main.rs` to
  initialization and the loop.
- Physics units are meters; rendering units are logical pixels. Convert at exactly one
  boundary, via a named constant. Do not mix them.
- Prefer explicit `f32` throughout to match Rapier's default feature set.

## Testing

There is no display in CI and no CI. Verify changes by running on the Pi and looking at the
TV. Where logic is display-independent (collision setup, scoring, state transitions), write
plain `#[test]` unit tests that can run on the Pi with `cargo test -j2`.
