#!/usr/bin/env bash
# Build the CRT visualizer, ship it, and leave it running until stopped.
#
#   ./scripts/viz.sh          build, then run detached on the Pi
#   ./scripts/viz.sh fg       run in the foreground so Ctrl-C stops it
#   ./scripts/viz.sh stop     stop whatever is running
#   ./scripts/viz.sh status   is it alive, and what rate is it holding
#
# On the Pi itself, `./piblob-viz --replace` takes the display from whatever
# already holds it, which saves a round trip when one is left running.
set -euo pipefail

cd "$(dirname "$0")/.."
HOST="${PI_HOST:-jake@raspberrypi.local}"
MODE="${1:-run}"

case "$MODE" in
  stop)
    ssh "$HOST" 'pkill -x piblob-viz || true'
    echo "stopped"
    exit 0
    ;;
  status)
    ssh "$HOST" 'pgrep -ax piblob-viz || echo "not running"; tail -3 ~/piblob-viz.log 2>/dev/null || true'
    exit 0
    ;;
esac

# tools/viz is deliberately outside the game's workspace so it can keep its own
# profile; build it by manifest path.
./scripts/cargo.sh build --manifest-path tools/viz/Cargo.toml
# Must stop it before the copy: rsync cannot overwrite a running binary.
ssh "$HOST" 'pkill -x piblob-viz || true'
rsync -az tools/viz/target/debug/viz "$HOST:piblob-viz"

case "$MODE" in
  fg)
    # -t so Ctrl-C reaches it and SDL restores the console.
    ssh -t "$HOST" './piblob-viz --replace'
    ;;
  *)
    ssh "$HOST" 'nohup ./piblob-viz --replace > ~/piblob-viz.log 2>&1 < /dev/null &'
    echo "running detached. stop it with: ./scripts/viz.sh stop"
    ;;
esac
