#!/usr/bin/env bash
# Sharing the hub cache with every user, in a stock ubuntu:22.04 (no acl until
# root installs it):
#   - root runs admin/share-hf-cache.sh: users with umask 077 add, update and
#     replace each other's entries through a 700 parent, a login shell carries
#     HF_HUB_CACHE, a re-run stacks nothing and leaves blobs read-only;
#   - a user runs the hf-cache Step on a directory they create: it is shared
#     without sudo, and a user who never ran anything can write to it.
#
#   tests/admin.sh
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

docker run --rm -i -v "$root:/mip:ro" ubuntu:22.04 bash -euo pipefail <<'EOF'
fail() { echo "FAIL: $*"; exit 1; }
as() { su - "$1" -c "umask 077; $2"; }
for u in alice bob carol dave; do useradd -m "$u"; done
mkdir -p /srv/locked && chmod 700 /srv/locked

bash /mip/admin/share-hf-cache.sh /srv/locked/hub
bash /mip/admin/share-hf-cache.sh --check /srv/locked/hub || fail "--check fails after sharing"
as alice 'mkdir -p "$HF_HUB_CACHE/models--x/refs" "$HF_HUB_CACHE/models--x/blobs" && echo a >"$HF_HUB_CACHE/models--x/refs/main"' \
  || fail "alice cannot write the cache"
as bob 'echo b >"$HF_HUB_CACHE/models--x/refs/main" && touch "$HF_HUB_CACHE/models--x/blobs/g"' \
  || fail "bob cannot update what alice created (both umask 077)"
as carol 'mv "$HF_HUB_CACHE/models--x/refs/main" "$HF_HUB_CACHE/models--x/refs/old"' || fail "carol cannot replace an entry"
[ "$(as alice 'echo $HF_HUB_CACHE')" = /srv/locked/hub ] || fail "HF_HUB_CACHE missing from a login shell"
chmod 444 /srv/locked/hub/models--x/blobs/g
bash /mip/admin/share-hf-cache.sh /srv/locked/hub >/dev/null
[ "$(grep -c '^HF_HUB_CACHE=' /etc/environment)" = 1 ] || fail "re-run stacked /etc/environment"
[ "$(stat -c %a /srv/locked/hub/models--x/blobs/g)" = 444 ] || fail "a re-run made a blob writable"
bash /mip/admin/share-hf-cache.sh relative 2>/dev/null && fail "a relative DIR was accepted"

# The hf-cache Step, as a user, no sudo: dave creates and shares /srv/team/hub.
mkdir -p /srv/team && chmod 1777 /srv/team
cfg='HF_HUB_CACHE_DIR=/srv/team/hub HF_HUB_CACHE_SHARED=yes'
su - dave -c "$cfg /mip/init.sh run hf-cache </dev/null" >/tmp/run.out 2>&1 || { cat /tmp/run.out; fail "hf-cache run failed"; }
grep -q 'hf-cache *ran' /tmp/run.out || { cat /tmp/run.out; fail "hf-cache did not run"; }
su - dave -c "$cfg bash /mip/lib/step.sh /mip/actions/hf-cache.sh check" || fail "hf-cache Check fails after sharing"
as dave 'mkdir -p /srv/team/hub/models--y && echo d >/srv/team/hub/models--y/f'
as carol 'echo c >>/srv/team/hub/models--y/f && mkdir /srv/team/hub/models--y/sub' || fail "another user cannot write the shared cache"
echo "admin: ok"
EOF
