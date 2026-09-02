# Bootstrap prompt

Paste the block below into your coding agent as the first task in this repository.

---

Bootstrap a Rust project in this repository called `piblob`.

**Target:** a Raspberry Pi 3 Model B running Raspberry Pi OS Lite (64-bit, Debian 13
trixie), with no desktop environment, displaying on a CRT television over composite video.
That is the only place it runs. It is built on the Mac inside an aarch64 Debian trixie
container that matches the Pi, via `./scripts/cargo.sh`; the Pi itself compiles nothing.
Read `AGENTS.md` before writing any code and treat its constraints as non-negotiable.

**Goal for this first pass:** the smallest thing that proves the whole stack works end to
end — a window-less SDL2 app rendering to the composite framebuffer, stepping a Rapier
simulation, responding to keyboard input. Gameplay comes later.

## Scaffold

Every cargo command runs through the container wrapper. There is no Rust on the Mac.

```bash
./scripts/cargo.sh init --name piblob
./scripts/cargo.sh add rapier2d
./scripts/cargo.sh add sdl2 --features use-pkgconfig
```

Do not write version numbers or API calls from memory. Let the registry resolve versions and
let the compiler tell you the current shape of Rapier's API; it changes between releases.

Add to `Cargo.toml`:

```toml
[profile.dev.package."*"]
opt-level = 3

[profile.dev]
debug = "line-tables-only"
```

Unoptimized Rapier is too slow to run at 60Hz on this hardware, while unoptimized game code
is fine and compiles much faster. That second half holds only while game code is
orchestrating rather than crunching. Per-pixel work written in this crate at `opt-level = 0`
is slow enough to miss vblank; `tools/viz` halves from 59.9Hz to 30Hz that way. The debuginfo setting keeps line numbers in panics and cuts
the binary from roughly 33MB to 13MB, which matters because that binary is copied to the Pi
on every iteration.

`tools/viz` already exists and is a separate package that the game must not depend on or
absorb. Cargo handles the two side by side with no workspace declaration; this was checked.
Do not add one, and do not modify that crate.

Do not create `.cargo/config.toml` to limit parallelism. The old `jobs = 2` setting existed
because the Pi has 1GB of RAM; the container has 8GB and six cores.

## Display initialization

- Force the KMSDRM video backend: `SDL_VIDEODRIVER=kmsdrm`, set from within the program via
  `sdl2::hint::set` before `sdl2::init()`, so it works regardless of how the binary is
  launched. Nothing sets this in the environment for you. Be aware that a plain hint is
  applied at normal priority and does **not** override an environment variable of the same
  name, so an inherited `SDL_VIDEODRIVER` still wins. That is useful for forcing the
  `dummy` driver in a test, and a trap if you assume the hint is authoritative.
- Create a fullscreen-desktop window. Do not request a specific window size; take whatever
  mode the composite connector reports (it will be 720x480).
- Set `SDL_HINT_RENDER_SCALE_QUALITY` to `"0"` for nearest-neighbour scaling.
- **Select the render driver explicitly.** Set `SDL_RENDER_DRIVER` to `software` before
  building the canvas, and assert that `canvas.info().name` really is `software`. SDL's
  default choice is `opengl`, which this board cannot provide, and it fails silently: the
  window appears, `clear()` works, `present()` page-flips at a plausible 60Hz, and every
  `fill_rect` draws nothing at all. You would spend a long time looking for a bug in your
  drawing code that is not there.
- **Build the canvas with `present_vsync`.** Without it `present()` returns immediately and
  the loop free-spins above 430Hz.
- Call `canvas.set_logical_size(320, 240)`. All drawing code works in this coordinate space
  and SDL handles the upscale.
- Hide the cursor.

## Structure

```
src/main.rs        init, the loop, shutdown
src/physics.rs     Rapier world wrapper
src/render.rs      all drawing, palette, safe-area constants, the units conversion
src/input.rs       SDL event pump -> a plain InputState struct
src/game.rs        game state and update logic
```

`render.rs` owns the safe area, the palette, and the one place pixels and meters meet:

```rust
pub const SAFE_X0: i32 = 32;
pub const SAFE_Y0: i32 = 24;
pub const SAFE_X1: i32 = 288;
pub const SAFE_Y1: i32 = 216;

pub const PIXELS_PER_METER: f32 = 32.0;
```

Expose the safe area in meters from `render.rs`, derived from those constants, and build the
demo scene from that. `physics.rs` and `game.rs` must never see a pixel value, and nothing
outside `render.rs` may multiply or divide by `PIXELS_PER_METER`. At this scale the safe area
is 8m by 6m and a 4px body is 0.125m, inside the range Rapier's defaults expect.

Also in `render.rs`: a named palette table of muted, low-saturation colors. No RGB literals
anywhere else.

## The loop

Fixed timestep. Accumulate real elapsed time, step Rapier in fixed `1.0/60.0` increments,
render once per iteration, present. Do not pass a variable delta to the physics step. Do not
allocate on the heap in game code inside the loop; Rapier's `step` allocates internally and
that is fine.

Cap the accumulator so a long stall cannot spiral into unbounded catch-up.

With `present_vsync` requested, `present()` has been measured blocking on vblank at a median
16.68ms, so the loop is already rate-limited and must not add a frame limiter of its own.
Do not code around NTSC's nominal 59.94Hz either; this mode presents at 59.9Hz and the
accumulator will land almost exactly one step per frame.

Drawing has room to spare: 200 filled rects cost 1.72ms of the 16.67ms frame through the
software renderer, and 800 cost 2.85ms. If the game runs slow, suspect the physics.

## Demo scene

- A static ground collider spanning the bottom of the safe area, and static walls at the
  left and right safe-area edges, all defined in meters.
- 20 dynamic circular rigid bodies with restitution around 0.6, spawned at pseudo-random
  positions in the upper half. Write a small xorshift or LCG in game code for this; do not
  add the `rand` crate. Seed it with a constant so a respawn is reproducible.
- Left/right arrow keys apply a horizontal impulse to all dynamic bodies. Space respawns
  them. Escape exits cleanly.
- Draw each body as a filled rect (a circle approximation is fine at this resolution) at
  minimum 4x4 logical pixels. Draw a 2px border around the safe area so the overscan
  behaviour is visible on the actual TV.

## Also produce

- `scripts/piblob.service` — a systemd unit that runs the binary on tty1 as user `jake`,
  with `Restart=always` so the game survives a crash and starts at boot. Give it
  `Conflicts=getty@tty1.service`, and note in the README that `run.sh` cannot acquire the
  display while this unit is running. `run.sh` places the binary at
  `/home/jake/PiBlob/piblob` for both profiles, so that is the path the unit should use.
- A short `docs/DISPLAY.md` recording exactly what you observed and what remains unverified.

## Constraints, restated

No winit, Bevy, macroquad, or wgpu. No async runtime. No ECS. No asset pipeline. No `rand`.
Single threaded. If a constraint in `AGENTS.md` makes a piece of this impossible, stop and
say so rather than working around it.

## Verification

You cannot see the TV. After building, state plainly which parts you verified (it compiles,
tests pass, it runs without panicking, the frame timing holds) and which parts require a
human looking at the screen (colors, overscan, interlace flicker, readability). Do not claim
the display output is correct.

The SDL2 KMSDRM backend, the composite mode, and the frame timing have all been confirmed
working on this board with a standalone probe, so a failure to open the display is a bug in
your code rather than an unknown in the platform. What remains unverified is everything a
human has to look at: colors over a composite signal, the real overscan boundary, interlace
flicker, and readability.
