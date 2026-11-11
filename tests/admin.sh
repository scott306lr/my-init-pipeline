#!/usr/bin/env bash
# admin/share-hf-cache.sh as root in a stock ubuntu:22.04 (no acl package): two
# users share the cache through a 700 parent, the login environment carries
# HF_HUB_CACHE, and a re-run is harmless.
#
#   tests/admin.sh
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

docker run --rm -i -v "$root/admin:/admin:ro" ubuntu:22.04 bash -euo pipefail <<'EOF'
fail() { echo "FAIL: $*"; exit 1; }
useradd -m alice; useradd -m bob; useradd -m carol
mkdir -p /srv/locked && chmod 700 /srv/locked
bash /admin/share-hf-cache.sh /srv/locked/hf/hub hf alice bob

su - alice -c 'mkdir -p "$HF_HUB_CACHE/models--x/blobs" && umask 077 && echo a >"$HF_HUB_CACHE/models--x/blobs/f"' \
  || fail "alice cannot write the cache"
su - bob -c 'echo b >>"$HF_HUB_CACHE/models--x/blobs/f" && touch "$HF_HUB_CACHE/models--x/blobs/g"' \
  || fail "bob cannot write what alice created (umask 077)"
[ "$(stat -c %G /srv/locked/hf/hub/models--x/blobs/f)" = hf ] || fail "new file is not in group hf"
su - carol -c 'touch /srv/locked/hf/hub/x' 2>/dev/null && fail "a non-member can write the cache"
[ "$(su - alice -c 'echo $HF_HUB_CACHE')" = /srv/locked/hf/hub ] || fail "HF_HUB_CACHE missing from a login shell"
grep -qx 'HF_HUB_CACHE=/srv/locked/hf/hub' /etc/environment || fail "/etc/environment not set"

bash /admin/share-hf-cache.sh /srv/locked/hf/hub hf carol >/dev/null
[ "$(grep -c '^HF_HUB_CACHE=' /etc/environment)" = 1 ] || fail "re-run stacked /etc/environment"
su - carol -c 'touch "$HF_HUB_CACHE/c"' || fail "an added user cannot write"
bash /admin/share-hf-cache.sh relative hf 2>/dev/null && fail "a relative DIR was accepted"
echo "admin: ok"
EOF
