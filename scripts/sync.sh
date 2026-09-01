#!/usr/bin/env bash
# Push the working tree to the Pi. Excludes target/ so the Pi keeps its build cache.
set -euo pipefail

HOST="${PI_HOST:-jake@raspberrypi.local}"
DEST="${PI_DEST:-PiBlob}"

cd "$(dirname "$0")/.."

# rsync rather than scp: only changed files move, which is the difference between a
# one-second sync and a twenty-second one on every iteration.
rsync -az --delete \
  --exclude-from=.rsyncignore \
  ./ "$HOST:$DEST/"

echo "synced -> $HOST:~/$DEST"
