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
3. **Choose the render driver explicitly. Never take SDL's default.** SDL picks `opengl`
   first, and VideoCore IV cannot provide it. The failure is silent and vicious: the
   window is created, `clear()` reaches the tube, `present()` page-flips at a convincing
   60Hz, and every `fill_rect` draws absolutely nothing. The result looks like a blank
   screen with no error anywhere. Set `SDL_RENDER_DRIVER` to `software` before building
   the canvas and assert on `canvas.info().name` afterwards. `opengles2` also works and is
   faster below roughly 250 rectangles, but software wins above that and is the better
   default here.
4. **Build the canvas with `present_vsync`.** Without it `present()` returns immediately
   and the loop free-spins at 430Hz or more, burning the CPU the physics needs. With it,
   `present()` blocks on vblank and the loop is rate-limited for free. Measured both ways
   on this board.
5. **Render at 320x240 internally.** Use `Canvas::set_logical_size(320, 240)` and let SDL
   upscale to the 720x480 composite framebuffer. Set `SDL_HINT_RENDER_SCALE_QUALITY` to `0`
   (nearest neighbour).
6. **Fixed timestep of 1/60s.** Accumulate wall-clock time and step Rapier in fixed
   increments. Never pass a variable frame delta to `PhysicsPipeline::step`. Cap the
   accumulator so a long stall cannot spiral into an unbounded catch-up loop. With vsync on,
   median frame time is 16.68ms, which is 59.9Hz, and the 59.94Hz NTSC broadcast figure does
   not describe this mode. The accumulator therefore lands almost exactly one step per frame
   and the drift worth worrying about is not there.
7. **Title-safe inset of 10%.** Nothing the player needs to read may be drawn outside
   x ∈ [32, 288] or y ∈ [24, 216] in logical coordinates. Define these as constants.
8. **One units boundary, and it lives in `render`.** Physics is in meters, drawing is in
   logical pixels, and `PIXELS_PER_METER = 32.0` is the single conversion constant. Derive
   the safe area in meters from the pixel constants there and hand those meters to scene
   setup, so `physics` and `game` never see a pixel. At that scale the safe area is 8m by
   6m and a 4px body is 0.125m, which sits inside the 0.1m to 1m range Rapier's defaults
   are tuned for. Do not convert anywhere else.
9. **No 1px horizontal features.** Interlacing strobes them. Minimum height 2px for any
   horizontal line, border, or text stroke.
10. **Muted palette.** Keep saturation low, especially in reds. Define the palette as a
    single named constant table; do not scatter RGB literals through drawing code.

## Performance budget

VideoCore IV, four A53 cores at 1.2GHz, 1GB RAM shared with the GPU, and no swap. Per frame
at 60Hz you have 16.67ms for physics plus rendering.

Drawing is not the constraint. Measured on the board, with vsync on and bodies drawn as
filled rects through the software renderer:

| Rects drawn | Draw time p50 | Frame budget |
|---|---|---|
| 20 | 1.43ms | 8.6% |
| 200 | 1.72ms | 10.3% |
| 400 | 2.08ms | 12.5% |
| 800 | 2.85ms | 17.1% |

Software has a fixed cost of roughly 1.4ms, dominated by the 320x240 to 720x480 upscale,
and then scales very flatly. `opengles2` starts far cheaper at 0.38ms for 20 rects but pays
per draw call, reaching 5.12ms at 800 where software is still at 2.85ms. They cross over
around 250 rects.

- Keep the rigid body count in the low hundreds. That ceiling is about Rapier's solver on a
  1.2GHz A53, not about drawing, which has budget to spare at every count measured.
- Prefer simple `fill_rect` / `draw_line` primitives. Do not reach for GLES shaders.
- No per-frame heap allocation **in game code**. Rapier's own `step` allocates internally;
  that is not something to work around.
- Do not add async runtimes, ECS frameworks, or asset pipelines. This is a single-threaded
  loop with a fixed set of dependencies.
- **Watch the dev profile if you write a hot loop.** `[profile.dev.package."*"]` optimises
  dependencies but leaves this crate's own code at `opt-level = 0`. That is the right trade
  while game code only orchestrates Rapier and SDL. It stops being right the moment game
  code touches every pixel: the visualizer in `tools/viz` runs at 30Hz unoptimised and
  59.9Hz optimised, from that change alone. If you add per-pixel or per-sample work, raise
  the profile and measure rather than assuming.

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

## tools/viz

`tools/viz` is a standalone plasma visualizer for the CRT, not part of the game. It is its
own package with its own profile and is not referenced by the game's manifest, so leave it
alone unless asked. It doubles as the most thorough display test in the repo: it exercises
streaming textures, the palette, vsync pacing, and the render-driver assertion all at once.
Drive it with `./scripts/viz.sh`.

## Testing

Display-independent logic (collision setup, scoring, state transitions, the units
conversion) gets plain `#[test]` unit tests, and those run in the container with
`./scripts/cargo.sh test` at full speed. There is no CI.

Anything involving the display cannot be tested here. Verify it by running on the Pi and
looking at the TV, and report what you did and did not confirm.
