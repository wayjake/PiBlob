# PiBlob

A Rust physics game built with [Rapier](https://rapier.rs), targeting the composite (RCA)
video output of a **Raspberry Pi 3 Model B**.

The Pi is the only place the game runs. It is not, however, where the game is built. Code is
edited on a Mac and compiled there inside an aarch64 Linux container that matches the Pi's
Debian release, and only the finished binary crosses the network.

---

## Hardware & display target

| | |
|---|---|
| Board | Raspberry Pi 3 Model B Rev 1.2 (Cortex-A53 @ 1.2GHz, 1GB RAM, VideoCore IV) |
| OS | Raspberry Pi OS Lite (64-bit, Debian 13 trixie) — no desktop environment |
| Output | Composite video on the 4-pole TRRS jack |
| Signal | NTSC, 720x480 interlaced, 4:3 |
| Internal render resolution | 320x240, nearest-neighbour upscaled by SDL |

Composite and HDMI are mutually exclusive. Once composite is enabled, the HDMI port goes
dark and SSH is your only way in.

### Design constraints imposed by the signal

These are not stylistic preferences. Violating them produces visible artifacts on a CRT.

- **No 1px horizontal lines.** Interlacing makes them strobe at 30Hz. Minimum 2px.
- **Title-safe area is ~90%.** Keep HUD, score, and anything readable inside a 10% inset.
  Assume the outer edge of the frame is not visible.
- **Desaturate reds.** Composite chroma bandwidth is narrow; saturated red smears
  horizontally. Prefer muted, low-saturation palettes.
- **Chunky shapes.** At an effective 320x240 with a soft analog signal, fine detail is lost.
  Design for readable silhouettes.
- **60Hz fixed timestep.** Step the physics at a fixed `1.0/60.0` and never feed a variable
  delta into Rapier. Measured, this mode presents at 60.0Hz rather than NTSC's nominal
  59.94Hz, and `present()` blocks on vblank, so the loop needs no frame limiter.

---

## Why the build happens in a container

The Mac is Apple Silicon, which is arm64. The Pi is aarch64 Linux. Those are the same CPU
architecture, so an arm64 Linux container on the Mac runs natively with no emulation, and
what it produces is a native binary for the Pi rather than a cross-compiled one.

Pinning the image to the Pi's own Debian release makes the runtime match exactly:

| | Pi | Build container |
|---|---|---|
| OS | Debian 13 trixie | Debian 13 trixie |
| Architecture | aarch64 | arm64 |
| glibc | 2.41 | 2.41 |
| SDL2 | 2.32.4 | 2.32.4 |
| Rust | none installed | 1.98 |

Rust comes from the container image rather than Debian's `apt`, whose 1.85 is below
rapier2d's declared minimum of 1.86.

The payoff is the iteration loop. Compiling Rapier on the Pi itself takes 15 to 30 minutes
and needs swap the board does not have. In the container it is seconds.

| | Measured |
|---|---|
| Cold build, rapier2d + sdl2, dependencies at `opt-level = 3` | 26s |
| Incremental rebuild of game code | 1.3s |
| Binary pushed to the Pi, `debug = "line-tables-only"` | 13MB |

## Measured display behaviour

Taken on the real board with SDL2 driving KMSDRM at 320x240 logical over the 720x480
composite mode.

| | Measured |
|---|---|
| Reported mode | 720x480 @ 60Hz, ARGB8888 |
| Present rate with `present_vsync` | 59.9Hz, median frame 16.68ms |
| Present rate without it | 431Hz software, 655Hz GLES |
| Draw time, 200 rects, software | 1.72ms, about 10% of a frame |
| Draw time, 800 rects, software | 2.85ms, about 17% of a frame |

Two findings here are load-bearing and neither is discoverable from the Mac.

**SDL's default render driver does not work on this hardware.** It picks `opengl` first,
which VideoCore IV cannot provide. Nothing errors. The window is created, `clear()` reaches
the tube, and `present()` page-flips at a convincing 60Hz, but every `fill_rect` silently
draws nothing, so the screen just sits there blank. Select `software` explicitly and check
`canvas.info().name` afterwards. `opengles2` works too and is quicker below roughly 250
rectangles, but software overtakes it above that.

**`present()` only blocks on vblank when the canvas asks for `present_vsync`.** Without it
the loop free-spins past 430Hz and eats the CPU the physics needs.

---

## One-time Mac setup

```bash
brew install colima docker
colima start --vm-type vz --mount-type virtiofs --cpu 6 --memory 8 --disk 40
```

Confirm the VM is the right architecture. This must say `aarch64`:

```bash
docker info --format '{{.Architecture}}'
```

Colima only mounts your home directory into the VM, so the repository has to live somewhere
under `/Users/<you>`.

If a Docker Desktop install was ever present, a stale `"credsStore": "desktop"` may remain
in `~/.docker/config.json` and will break image pulls with `docker-credential-desktop:
executable file not found`. Remove that key.

---

## One-time Pi setup

Flash Raspberry Pi OS Lite (64-bit), enable SSH, then copy the provisioning script over and
run it **on the Pi**:

```bash
scp scripts/setup-pi.sh jake@raspberrypi.local:
ssh jake@raspberrypi.local
./setup-pi.sh
sudo reboot
```

It is safe to re-run. It does four things.

It installs the SDL2 runtime **and an EGL stack**. The EGL packages are not optional and
apt will not pull them in on its own: SDL2 loads `libEGL.so.1` at runtime rather than
linking against it, so there is no recorded dependency, but its KMSDRM backend builds
every window on a GBM surface behind an EGL display. Without them SDL brings up the video
driver and then fails window creation with `EGL not initialized`, even if you only ever
intend to use the software renderer.

It appends `,composite` to the KMS overlay in `/boot/firmware/config.txt` and sets
`enable_tvout=1`.

It installs a small systemd unit that **forces the composite connector to report
connected**. Analog video has no load detection, so the encoder reports this connector as
`unknown` forever, even with a TV attached and visibly displaying a picture. SDL2 counts a
connector as usable only when it reports `connected` with at least one mode, so it
concludes there is no display at all and refuses to start KMSDRM. Forcing the status is
what makes the whole stack work. This is done with a unit rather than a `video=` kernel
argument because a malformed `cmdline.txt` on a board whose only output is composite is
painful to recover from.

It adds you to the `video`, `render`, and `input` groups. Outside of X, SDL reads input
directly from evdev, and without the `input` group the game runs fine and silently
receives no key events.

It does not install Rust, a compiler, or swap. The Pi needs none of them.

After the reboot you can confirm composite is live without looking at the TV:

```bash
ls /sys/class/drm/     # expect a card0-Composite-1 entry
```

---

## Development workflow

Edit on the Mac. Build in the container. Run on the Pi.

```bash
./scripts/cargo.sh build      # or add, test, clippy — any cargo command
./scripts/run.sh              # build, ship the binary, launch it on the Pi
PROFILE=release ./scripts/run.sh
```

`scripts/cargo.sh` bind-mounts the repository into the container and keeps the crates.io
registry in a named volume, so dependency resolution stays warm between runs. It runs as
your own uid, so files it writes into the tree are yours and not root's.

### Running

The game must own the display. Two options:

**Over SSH** (normal iteration) — what `run.sh` does. Works as long as nothing else holds
DRM master.

**As a systemd unit on tty1** (what shipping looks like) — see `scripts/piblob.service`
generated by the bootstrap. Give it `Conflicts=getty@tty1.service`, and note that while it
is enabled with `Restart=always`, `run.sh` can never acquire the display. Stop the unit
first.

---

## The visualizer

`tools/viz` draws a plasma field under moving copper bars, with muted palettes that
regenerate at random every eighteen seconds and crossfade between. It exists to be looked
at, and it is also the most complete display test here: it exercises streaming textures,
vsync pacing, the palette rules, and the render-driver assertion in one go.

```bash
./scripts/viz.sh          # build and leave it running on the Pi
./scripts/viz.sh fg       # run in the foreground, Ctrl-C to stop
./scripts/viz.sh stop
./scripts/viz.sh status
```

It holds 59.9Hz. It writes all 76,800 pixels itself each frame, which is why its own
package optimises local code rather than only dependencies.

---

## Debugging

| Symptom | Cause |
|---|---|
| Black screen, no bootsplash | Composite not enabled in `config.txt`, or wrong TRRS cable pinout |
| Bootsplash appears, game doesn't | Video driver not KMSDRM — check `SDL_VIDEODRIVER=kmsdrm` |
| `libSDL2-2.0.so.0: cannot open shared object file` | `setup-pi.sh` has not run; the SDL2 runtime is missing |
| `kmsdrm not available` | Either another process already holds the display, or no connector reports `connected`. Check `pgrep -ax piblob-viz` first, then the composite force unit |
| `EGL not initialized` | `libegl1` / `libegl-mesa0` missing; SDL2 dlopens EGL so apt never required it |
| Blank screen, no error, timing looks right | SDL defaulted to the `opengl` renderer; force `software` |
| `No available video device` | Generic SDL form of the same contention. On this board it usually surfaces as `kmsdrm not available` instead |
| Game runs, ignores input | User not in the `input` group |
| Picture rolls or goes B&W | PAL/NTSC mismatch — set `vc4.tv_norm=` in `cmdline.txt` |
| Edges of the UI cut off | Not respecting the title-safe inset |
| `docker-credential-desktop: not found` | Stale `credsStore` in `~/.docker/config.json` |

Note the TRRS pinout: on the standard Raspberry Pi cable, composite video comes out of the
**red** connector, not the yellow one, on many third-party cables. Check both.

---

## Repository layout

```
AGENTS.md              Conventions and constraints for coding agents
BOOTSTRAP_PROMPT.md    The prompt used to generate the initial application
CLAUDE.md              Guidance for Claude Code
docker/Dockerfile      The aarch64 Debian trixie build image
scripts/cargo.sh       Run any cargo command inside that image
scripts/run.sh         Build, ship the binary to the Pi, and launch it
scripts/setup-pi.sh    One-time Pi provisioning
scripts/viz.sh         Build, run, and stop the CRT visualizer
tools/viz/             Standalone plasma visualizer, not part of the game
src/                   Game source
```
