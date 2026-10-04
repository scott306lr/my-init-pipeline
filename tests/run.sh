#!/usr/bin/env bash
# Run the bats suite, fetching bats-core into tests/.bats on first use.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if command -v bats >/dev/null; then
  bats_bin=bats
else
  [ -x "$here/.bats/bin/bats" ] || git clone -q --depth 1 https://github.com/bats-core/bats-core "$here/.bats"
  bats_bin="$here/.bats/bin/bats"
fi
exec "$bats_bin" "$@" "$here"/*.bats
