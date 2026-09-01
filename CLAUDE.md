# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

Read `AGENTS.md` before touching code. Its hard constraints (Pi-only target, SDL2/KMSDRM,
320x240 logical render, fixed 1/60 timestep, title-safe inset, no 1px horizontal lines,
muted palette, permitted crates) are binding and are not restated here. `README.md` covers
Pi provisioning, the composite-video signal constraints, and a symptom/cause debugging table.

## Current state

The repository is **not yet bootstrapped**. There is no `Cargo.toml`, no `src/`, no `docs/`,
and no `scripts/piblob.service`. The first task is the prompt in `BOOTSTRAP_PROMPT.md`.
The layout below is the *intended* structure from that prompt, not existing code; rewrite
this section once the crate exists.

```
src/main.rs     init, fixed-timestep loop, shutdown — nothing else
src/physics.rs  Rapier world wrapper; units are meters
src/render.rs   all drawing, the palette table, SAFE_X0/Y0/X1/Y1 constants; units are logical pixels
src/input.rs    SDL event pump -> plain InputState struct
src/game.rs     game state and update logic
```

Meters-to-pixels conversion happens at exactly one boundary via a named constant.

**The Pi is not provisioned yet.** As of the last check it had no Rust toolchain, no SDL2,
no swap, and composite output still disabled in `config.txt`. Run `scripts/setup-pi.sh` on
the Pi before expecting any build to work. Re-probe rather than trusting this paragraph.

**The Pi runs Debian 13 (trixie), not Bookworm.** Every doc in this repo says Bookworm.
Treat package names and versions from those docs as unverified on this host.

## Commands

Every build runs **on the Pi over SSH**. `cargo build` on the Mac fails at the SDL2 link
step, and there is currently no Rust toolchain on the Mac at all. Both scripts honor
`PI_HOST` (default `jake@raspberrypi.local`) and `PI_DEST` (default `PiBlob`).

| Task | Command |
|---|---|
| Provision the Pi (run on the Pi) | `scripts/setup-pi.sh` |
| Sync tree to Pi | `./scripts/sync.sh` |
| Sync, build, launch | `./scripts/run.sh` |
| Build only | `ssh $PI_HOST 'cd PiBlob && cargo build -j2'` |
| Run all tests | `ssh $PI_HOST 'cd PiBlob && cargo test -j2'` |
| Run one test | `ssh $PI_HOST 'cd PiBlob && cargo test -j2 <test_name>'` |

Always pass `-j2`; four parallel `rustc` processes OOM the 1GB board.

If a remote `cargo` invocation reports `command not found`, that is expected for a rustup
install: `ssh host 'cmd'` runs a non-interactive shell that sources neither `.bashrc` nor
`.profile`, so `~/.cargo/bin` is not on `PATH`. Use the absolute path `~/.cargo/bin/cargo`.

## Gotchas for agent sessions

- **First build is 15–30 minutes.** The Bash tool times out at 10 minutes. Run the remote
  build in the background, or split build from launch.
- **Don't launch the game from a blocking call.** `run.sh` uses `ssh -t` and runs the game
  in the foreground. With no TTY there is no Ctrl-C and nobody presses Escape, so the
  process keeps DRM master and the next launch fails with `No available video device`.
  Clear it with `ssh $PI_HOST pkill piblob` if it was started by `run.sh`, or
  `ssh $PI_HOST sudo systemctl stop piblob` once the systemd unit exists — under
  `Restart=always` a bare `pkill` just makes systemd start it again.
- **You cannot see the TV.** Report what was verified (compiles, runs without panicking,
  frame timing) separately from what needs a human at the screen (colors, overscan,
  interlace flicker, readability). Never claim display output is correct. See the
  Verification section of `BOOTSTRAP_PROMPT.md`.
