#!/usr/bin/env bash
# Run tests/share-root.sh as root where it can do no harm: in CI, directly on
# the runner (a throwaway VM that has root and acl, and needs no network);
# elsewhere, in a stock ubuntu:22.04 container, which also covers installing
# acl when setfacl is missing (that needs network to the Ubuntu mirror).
#
#   tests/admin.sh
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ "${CI:-}" = true ]; then
  sudo bash "$root/tests/share-root.sh" "$root"
else
  docker run --rm -v "$root:/src:ro" ubuntu:22.04 bash /src/tests/share-root.sh /src
fi
