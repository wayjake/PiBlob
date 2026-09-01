# Build environment for PiBlob.
#
# The Mac is Apple Silicon (arm64) and the Pi is aarch64 Linux: the same CPU
# architecture. This image therefore runs natively under virtualization with no
# emulation, and what it produces is a native aarch64 Linux binary rather than a
# cross-compiled one. There is still no macOS build.
#
# The image is pinned to the Pi's own Debian release so the runtime matches:
#
#            | Pi                     | this image
#   ---------|------------------------|------------------------
#   OS       | Debian 13 trixie       | Debian 13 trixie
#   arch     | aarch64                | arm64
#   glibc    | 2.41                   | 2.41
#   SDL2     | 2.32.4                 | 2.32.4
#
# Rust comes from the image (1.98) and not from Debian's apt (1.85), which is
# below rapier2d's declared minimum of 1.86.
FROM rust:1-slim-trixie

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libsdl2-dev \
      pkg-config \
 && rm -rf /var/lib/apt/lists/*

# The container runs as the host user's uid so that files it writes into the
# bind-mounted repo are owned by that user rather than root. The official rust
# image already makes CARGO_HOME world-writable; these directories are created
# here so a named volume mounted over the registry inherits those permissions.
RUN mkdir -p "$CARGO_HOME/registry" "$CARGO_HOME/git" && chmod -R 777 "$CARGO_HOME"

WORKDIR /work
