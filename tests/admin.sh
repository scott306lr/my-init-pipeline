#!/usr/bin/env bash
# admin/share-hf-cache.sh as root in a stock ubuntu:22.04 (no acl package): two
# users share the cache through a 700 parent, the login environment carries
# HF_HUB_CACHE, and a re-run is harmless. Then the hf-share Step for real: run
# by a user with passwordless sudo, and refused (with the admin command) without.
#
#   tests/admin.sh
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

docker run --rm -i -v "$root:/mip:ro" ubuntu:22.04 bash -euo pipefail <<'EOF'
fail() { echo "FAIL: $*"; exit 1; }
useradd -m alice; useradd -m bob; useradd -m carol
mkdir -p /srv/locked && chmod 700 /srv/locked
bash /mip/admin/share-hf-cache.sh /srv/locked/hf/hub hf alice bob

su - alice -c 'mkdir -p "$HF_HUB_CACHE/models--x/blobs" && umask 077 && echo a >"$HF_HUB_CACHE/models--x/blobs/f"' \
  || fail "alice cannot write the cache"
su - bob -c 'echo b >>"$HF_HUB_CACHE/models--x/blobs/f" && touch "$HF_HUB_CACHE/models--x/blobs/g"' \
  || fail "bob cannot write what alice created (umask 077)"
[ "$(stat -c %G /srv/locked/hf/hub/models--x/blobs/f)" = hf ] || fail "new file is not in group hf"
su - carol -c 'touch /srv/locked/hf/hub/x' 2>/dev/null && fail "a non-member can write the cache"
[ "$(su - alice -c 'echo $HF_HUB_CACHE')" = /srv/locked/hf/hub ] || fail "HF_HUB_CACHE missing from a login shell"
grep -qx 'HF_HUB_CACHE=/srv/locked/hf/hub' /etc/environment || fail "/etc/environment not set"

bash /mip/admin/share-hf-cache.sh /srv/locked/hf/hub hf carol >/dev/null
[ "$(grep -c '^HF_HUB_CACHE=' /etc/environment)" = 1 ] || fail "re-run stacked /etc/environment"
su - carol -c 'touch "$HF_HUB_CACHE/c"' || fail "an added user cannot write"
bash /mip/admin/share-hf-cache.sh relative hf 2>/dev/null && fail "a relative DIR was accepted"
# The hf-share Step: dave has passwordless sudo, so it runs without a terminal
# and the new directory is his; erin has no sudo and gets the admin command.
apt-get install -y -qq sudo >/dev/null
useradd -m dave; useradd -m erin
echo 'dave ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/dave
step() { su - "$1" -c "HF_SHARE_GROUP=team HF_HUB_CACHE_DIR=/srv/team/hub bash /mip/lib/step.sh /mip/actions/hf-share.sh $2"; }
step dave check && fail "hf-share Check passed before setup"
su - dave -c 'HF_SHARE_GROUP=team HF_HUB_CACHE_DIR=/srv/team/hub /mip/init.sh run hf-share </dev/null' >/tmp/run.out 2>&1 \
  || { cat /tmp/run.out; fail "hf-share run failed"; }
grep -q 'hf-share *ran' /tmp/run.out || { cat /tmp/run.out; fail "hf-share did not run"; }
step dave check || fail "hf-share Check fails after setup"
[ "$(stat -c %U:%G /srv/team/hub)" = dave:team ] || fail "new directory is not dave's, in group team"
step erin check && fail "hf-share Check passes for a non-member"
step erin run >/tmp/erin.out 2>&1 && fail "hf-share run succeeded without sudo"
grep -q 'ask an admin to run' /tmp/erin.out || { cat /tmp/erin.out; fail "no admin command for erin"; }
echo "admin: ok"
EOF
