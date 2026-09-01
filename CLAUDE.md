# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

Read `AGENTS.md` before touching code. Its hard constraints (container-only builds,
SDL2/KMSDRM, 320x240 logical render, fixed 1/60 timestep, the single units boundary,
title-safe inset, no 1px horizontal lines, muted palette, permitted crates) are binding and
are not restated here. `README.md` covers Mac and Pi setup, why the build runs in a
container, and a symptom/cause debugging table.

## Current state

The repository is **not yet bootstrapped**. There is no `Cargo.toml`, no `src/`, no `docs/`,
and no `scripts/piblob.service`. The first task is the prompt in `BOOTSTRAP_PROMPT.md`.
The layout below is the *intended* structure from that prompt, not existing code; rewrite
this section once the crate exists.

```
src/main.rs     init, fixed-timestep loop, shutdown — nothing else
src/physics.rs  Rapier world wrapper; meters only
src/render.rs   drawing, palette, safe-area constants, PIXELS_PER_METER
src/input.rs    SDL event pump -> plain InputState struct
src/game.rs     game state and update logic; meters only
```

**The Pi is provisioned and the display stack is verified.** A standalone probe built in the
container brought up SDL2 on KMSDRM at 720x480 @ 60Hz, created a window, and presented 300
frames at 60.14Hz with a 16.668ms median and no long frames. The build container is equally
verified: an aarch64 ELF whose libc, libm, and libgcc_s all resolve against the Pi's own
libraries. Re-probe rather than trusting this paragraph.

Two things about that stack are easy to break and hard to diagnose. SDL2 refuses to start
KMSDRM unless some connector reports `connected`, and composite reports `unknown` forever
because analog video cannot detect a load, so a systemd unit forces it. SDL2 also dlopens
`libEGL.so.1`, which means apt records no dependency and the EGL packages have to be
installed explicitly. `scripts/setup-pi.sh` handles both, but it needs an interactive sudo
password, so a human has to run it.

## Commands

Every cargo command runs inside the container. There is no Rust toolchain on the Mac.

| Task | Command |
|---|---|
| Any cargo command | `./scripts/cargo.sh <args>` |
| Build | `./scripts/cargo.sh build` |
| Run all tests | `./scripts/cargo.sh test` |
| Run one test | `./scripts/cargo.sh test <test_name>` |
| Build, ship, and run on the Pi | `./scripts/run.sh` |
| Same, release profile | `PROFILE=release ./scripts/run.sh` |

`run.sh` honors `PI_HOST` (default `jake@raspberrypi.local`) and `PI_DEST` (default
`PiBlob`). Do not pass `-j2`; that existed for the Pi's 1GB of RAM and no longer applies.

## Gotchas for agent sessions

- **Colima must be running.** It does not survive a reboot on its own. If docker commands
  fail to connect, `colima start`. A first start pulls a VM image and can exceed the Bash
  tool's 10 minute timeout, so background it.
- **Check exit codes, not just output.** Piping a build through `tail` masks failure,
  because the pipeline reports the exit status of `tail`. A Docker build that printed a
  clean-looking tail had in fact failed here.
- **Don't launch the game from a blocking call.** `run.sh` ends with `ssh -t` and runs the
  game in the foreground. With no TTY there is no Ctrl-C and nobody presses Escape, so the
  process keeps DRM master and the next launch fails with `No available video device`.
  `run.sh` already pkills a stale instance, but once the systemd unit exists a bare pkill
  only makes systemd restart it. Use `ssh $PI_HOST sudo systemctl stop piblob`.
- **Sudo on the Pi requires a password.** Anything needing root there has to be handed to
  the user; it cannot be scripted from here.
- **You cannot see the TV.** Report what was verified (compiles, tests pass, runs without
  panicking, frame timing) separately from what needs a human at the screen (colors,
  overscan, interlace flicker, readability). Never claim display output is correct. See the
  Verification section of `BOOTSTRAP_PROMPT.md`.
