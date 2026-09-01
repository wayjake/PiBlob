#!/usr/bin/env bash
# Run cargo inside the aarch64 Linux build container.
#
# Every cargo invocation for this project goes through here: build, add, test,
# init, clippy. There is no Rust toolchain on the Mac and none is wanted. The
# container targets the same Debian release and architecture as the Pi, so its
# output runs there unmodified.
#
#   ./scripts/cargo.sh build
#   ./scripts/cargo.sh add rapier2d
#   ./scripts/cargo.sh test
set -euo pipefail

cd "$(dirname "$0")/.."

IMAGE="${PIBLOB_IMAGE:-piblob-build}"

if ! docker image inspect "$IMAGE" > /dev/null 2>&1; then
  echo "==> building $IMAGE (first run only)"
  docker build -t "$IMAGE" docker/
fi

# -t only when stdin is a terminal; without the guard this breaks under CI,
# pipes, and agent tooling.
tty_flag=()
[ -t 0 ] && tty_flag=(-t)

# --user keeps files written into the bind-mounted repo owned by the invoking
# user instead of root. The named volume persists the crates.io registry cache
# between runs, which is the difference between a cold and warm dependency
# resolve.
exec docker run --rm -i ${tty_flag[@]+"${tty_flag[@]}"} \
  --user "$(id -u):$(id -g)" \
  -v "$PWD:/work" \
  -v piblob-cargo-registry:/usr/local/cargo/registry \
  -w /work \
  "$IMAGE" \
  cargo "$@"
