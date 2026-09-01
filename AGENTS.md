# AGENTS.md

Instructions for coding agents working in this repository.

## What this project is

A 2D physics game in Rust using Rapier, rendered with SDL2, running on a Raspberry Pi 3
Model B and displayed on a CRT over composite video.

## Hard constraints

Do not violate these. They come from the hardware, not from taste.

1. **The Pi is the only run target, and the container is the only build target.** Builds
   happen in an aarch64 Debian trixie container on the Mac, which is the same architecture
   and Debian release the Pi runs, so its output is a native binary rather than a
   cross-compiled one. The Pi compiles nothing. There is still no macOS build, no windowed
   preview mode, and no `cfg` branching for other platforms. Every cargo command goes
   through `./scripts/cargo.sh`.
2. **SDL2 with the KMSDRM backend.** No winit, no Bevy, no macroquad, no wgpu. Those
   require X11 or Wayland; there is no display server on this device.
3. **Render at 320x240 internally.** Use `Canvas::set_logical_size(320, 240)` and let SDL
   upscale to the 720x480 composite framebuffer. Set `SDL_HINT_RENDER_SCALE_QUALITY` to `0`
   (nearest neighbour).
4. **Fixed timestep of 1/60s.** Accumulate wall-clock time and step Rapier in fixed
   increments. Never pass a variable frame delta to `PhysicsPipeline::step`. Cap the
   accumulator so a long stall cannot spiral into an unbounded catch-up loop.
   Measured on this board: `present()` blocks on vblank, so the loop is rate-limited for
   free and must not add a frame limiter of its own. Median frame time is 16.668ms, which
   is 59.99Hz, with zero frames beyond 1.5x median across 300 samples. The 59.94Hz NTSC
   broadcast figure does not describe this mode, so the accumulator lands almost exactly
   one step per frame and the drift worth worrying about is not there.
5. **Title-safe inset of 10%.** Nothing the player needs to read may be drawn outside
   x ∈ [32, 288] or y ∈ [24, 216] in logical coordinates. Define these as constants.
6. **One units boundary, and it lives in `render`.** Physics is in meters, drawing is in
   logical pixels, and `PIXELS_PER_METER = 32.0` is the single conversion constant. Derive
   the safe area in meters from the pixel constants there and hand those meters to scene
   setup, so `physics` and `game` never see a pixel. At that scale the safe area is 8m by
   6m and a 4px body is 0.125m, which sits inside the 0.1m to 1m range Rapier's defaults
   are tuned for. Do not convert anywhere else.
7. **No 1px horizontal features.** Interlacing strobes them. Minimum height 2px for any
   horizontal line, border, or text stroke.
8. **Muted palette.** Keep saturation low, especially in reds. Define the palette as a
   single named constant table; do not scatter RGB literals through drawing code.

## Performance budget

VideoCore IV, four A53 cores at 1.2GHz, 1GB RAM shared with the GPU, and no swap. Per frame
at 60Hz you have ~16ms for physics plus rendering. Build speed is no longer a constraint,
but everything about the runtime still is.

- Keep the rigid body count in the low hundreds.
- Prefer the SDL software renderer or simple `fill_rect` / `draw_line` primitives. Do not
  reach for GLES shaders.
- No per-frame heap allocation **in game code**. Rapier's own `step` allocates internally;
  that is not something to work around.
- Do not add async runtimes, ECS frameworks, or asset pipelines. This is a single-threaded
  loop with a fixed set of dependencies.

## Dependencies

Add crates with `./scripts/cargo.sh add` so versions resolve against the current registry.
Do not pin versions from memory, and do not write API calls from memory either. Rapier's
surface changes between releases; let the compiler tell you the current shape.

Permitted: `rapier2d`, `nalgebra` (re-exported by Rapier), `sdl2`. Adding anything else
requires an explicit reason in the commit message.

Do **not** add `rand`. Where the game needs randomness, hand-roll a small xorshift or LCG in
game code. It is a few lines, it adds no dependency, and deterministic seeding makes a
respawn reproducible, which matters when the only way to observe a bug is watching a CRT.

Configure `sdl2` with the `use-pkgconfig` feature so it links against the system library.
Do **not** enable the `bundled` feature.

## Commands

| Task | Command |
|---|---|
| Any cargo command | `./scripts/cargo.sh <args>` |
| Build | `./scripts/cargo.sh build` |
| Test | `./scripts/cargo.sh test` |
| Build, ship, and run on the Pi | `./scripts/run.sh` |
| Provision the Pi (run on the Pi) | `scripts/setup-pi.sh` |

Never run `cargo` directly. There is no Rust toolchain on the Mac and none is wanted.

## Code style

- Rust 2021 or later, `rustfmt` defaults.
- Modules split by responsibility: `physics`, `render`, `input`, `game`. Keep `main.rs` to
  initialization and the loop.
- Prefer explicit `f32` throughout to match Rapier's default feature set.

## Testing

Display-independent logic (collision setup, scoring, state transitions, the units
conversion) gets plain `#[test]` unit tests, and those run in the container with
`./scripts/cargo.sh test` at full speed. There is no CI.

Anything involving the display cannot be tested here. Verify it by running on the Pi and
looking at the TV, and report what you did and did not confirm.
