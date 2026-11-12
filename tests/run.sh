#!/usr/bin/env bash
# Run the bats suite, fetching the pinned bats-core into tests/.bats on first use.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# One bats for everyone, pinned: the tests use `run -N` (1.5) and the
# bats::on_failure hook (1.12), which a distribution's bats may predate.
BATS_VERSION=1.14.0
bats_bin="$here/.bats/bin/bats"
if [ "$("$bats_bin" --version 2>/dev/null)" != "Bats $BATS_VERSION" ]; then
  # Fetch beside the old copy and swap, so a failed fetch leaves it in place.
  fetched="$here/.bats.fetching"
  rm -rf "$fetched"
  git -c advice.detachedHead=false clone -q --depth 1 --branch "v$BATS_VERSION" https://github.com/bats-core/bats-core "$fetched" || {
    echo "tests/run.sh: could not fetch bats $BATS_VERSION (needed once; needs network)" >&2
    exit 1
  }
  rm -rf "$here/.bats"
  mv "$fetched" "$here/.bats"
fi
exec "$bats_bin" "$@" "$here"/*.bats
