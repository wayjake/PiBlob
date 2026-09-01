# Bootstrap prompt

Paste the block below into your coding agent as the first task in this repository.

---

Bootstrap a Rust project in this repository called `piblob`.

**Target:** a Raspberry Pi 3 Model B+ running Raspberry Pi OS Lite (64-bit, Bookworm), with
no desktop environment, displaying on a CRT television over composite video. This is the
only target. There is no desktop build and no cross-compilation. Read `AGENTS.md` before
writing any code and treat its constraints as non-negotiable.

**Goal for this first pass:** the smallest thing that proves the whole stack works end to
end — a window-less SDL2 app rendering to the composite framebuffer, stepping a Rapier
simulation, responding to keyboard input. Gameplay comes later.

## Scaffold

Create a binary crate with `cargo init --name piblob`. Add dependencies with `cargo add
rapier2d sdl2` — do not write version numbers from memory, let the registry resolve them.
Ensure `sdl2` links against the system SDL2 (Bookworm's `libsdl2-dev`) and that the
`bundled` feature is **off**.

Add to `Cargo.toml`:

```toml
[profile.dev.package."*"]
opt-level = 3
```

Unoptimized Rapier is too slow to run at 60Hz on this hardware; unoptimized game code is
fine and compiles much faster.

Create `.cargo/config.toml` setting `jobs = 2` — the board has 1GB of RAM and four parallel
`rustc` processes will OOM.

## Display initialization

- Force the KMSDRM video backend: `SDL_VIDEODRIVER=kmsdrm`, set from within the program via
  `sdl2::hint::set` before `sdl2::init()`, so it works regardless of how the binary is
  launched.
- Create a fullscreen-desktop window. Do not request a specific window size; take whatever
  mode the composite connector reports (it will be 720x480).
- Set `SDL_HINT_RENDER_SCALE_QUALITY` to `"0"` for nearest-neighbour scaling.
- Call `canvas.set_logical_size(320, 240)`. All drawing code works in this coordinate space
  and SDL handles the upscale.
- Hide the cursor.

## Structure

```
src/main.rs        init, the loop, shutdown
src/physics.rs     Rapier world wrapper
src/render.rs      all drawing, palette, safe-area constants
src/input.rs       SDL event pump -> a plain InputState struct
src/game.rs        game state and update logic
```

`render.rs` owns:

```rust
pub const SAFE_X0: i32 = 32;
pub const SAFE_Y0: i32 = 24;
pub const SAFE_X1: i32 = 288;
pub const SAFE_Y1: i32 = 216;
```

and a named palette table of muted, low-saturation colors. No RGB literals anywhere else.

## The loop

Fixed timestep. Accumulate real elapsed time, step Rapier in fixed `1.0/60.0` increments,
render once per iteration, present. Do not pass a variable delta to the physics step. Do not
allocate on the heap inside the loop.

## Demo scene

- A static ground collider spanning the bottom of the safe area, and static walls at the
  left and right safe-area edges.
- 20 dynamic circular rigid bodies with restitution around 0.6, spawned at random positions
  in the upper half.
- Left/right arrow keys apply a horizontal impulse to all dynamic bodies. Space respawns
  them. Escape exits cleanly.
- Draw each body as a filled rect (a circle approximation is fine at this resolution) at
  minimum 4x4 logical pixels. Draw a 2px border around the safe area so the overscan
  behaviour is visible on the actual TV.

## Also produce

- `scripts/piblob.service` — a systemd unit that runs the release binary on tty1 as user
  `jake`, with `Restart=always`, so the game survives a crash and starts at boot.
- A short `docs/DISPLAY.md` recording exactly what you observed and what remains unverified.

## Constraints, restated

No winit, Bevy, macroquad, or wgpu. No async runtime. No ECS. No asset pipeline. Single
threaded. If a constraint in `AGENTS.md` makes a piece of this impossible, stop and say so
rather than working around it.

## Verification

You cannot see the TV. After building, state plainly which parts you verified (it compiles,
it runs without panicking, the frame timing holds) and which parts require a human looking
at the screen (colors, overscan, interlace flicker, readability). Do not claim the display
output is correct.
