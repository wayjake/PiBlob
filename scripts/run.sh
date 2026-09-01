#!/usr/bin/env bash
# Build in the container, ship the binary to the Pi, and run it.
#
# Nothing is compiled on the Pi. The container produces a native aarch64 Linux
# binary, so only that one file crosses the network.
set -euo pipefail

cd "$(dirname "$0")/.."

HOST="${PI_HOST:-jake@raspberrypi.local}"
DEST="${PI_DEST:-PiBlob}"
PROFILE="${PROFILE:-dev}"

case "$PROFILE" in
  dev)     build_args=();          bin="target/debug/piblob"   ;;
  release) build_args=(--release); bin="target/release/piblob" ;;
  *) echo "PROFILE must be 'dev' or 'release', got '$PROFILE'" >&2; exit 2 ;;
esac

./scripts/cargo.sh build ${build_args[@]+"${build_args[@]}"}

# The game holds DRM master for as long as it runs, and an instance left behind
# by an earlier launch makes the next one fail with "No available video device".
# That is easy to do from a non-interactive session, where nothing ever delivers
# Ctrl-C or Escape. Clear it before pushing.
#
# Once piblob.service exists this is not enough on its own: under Restart=always
# systemd simply starts it again. Stop the unit first.
ssh "$HOST" "mkdir -p '$DEST'; pkill -x piblob || true"

rsync -az "$bin" "$HOST:$DEST/piblob"

# -t allocates a TTY so Ctrl-C reaches the game and SDL restores the console on
# exit. SDL_VIDEODRIVER is deliberately not set here: the program sets the hint
# itself, which is what makes it behave identically under systemd.
ssh -t "$HOST" "cd '$DEST' && ./piblob"
