#!/usr/bin/env bash
# Sync, build, and run on the Pi.
set -euo pipefail

HOST="${PI_HOST:-jake@raspberrypi.local}"
DEST="${PI_DEST:-PiBlob}"

"$(dirname "$0")/sync.sh"

# -t allocates a TTY so Ctrl-C reaches the game and SDL restores the console on exit.
ssh -t "$HOST" "cd $DEST && cargo build -j2 && SDL_VIDEODRIVER=kmsdrm ./target/debug/piblob"
