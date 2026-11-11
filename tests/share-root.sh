#!/usr/bin/env bash
# Sharing the hub cache with every user, as root on a throwaway machine (it adds
# users and writes /etc/profile.d): run by tests/admin.sh, in ubuntu:22.04
# locally and directly on the CI runner.
#   - root runs admin/share-hf-cache.sh: users with umask 077 add, update and
#     replace each other's entries through a 700 parent, a login shell carries
#     HF_HUB_CACHE, a re-run stacks nothing and leaves blobs read-only;
#   - a user runs the hf-cache Step on a directory they create: it is shared
#     without sudo, and a user who never ran anything can write to it;
#   - the optional hf-export Step, named, makes that directory every user's
#     HF_HUB_CACHE with sudo;
#   - init.sh refuses to run as root.
#
#   tests/share-root.sh REPO_DIR    (as root)
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run as root on a throwaway machine" >&2; exit 2; }
# A copy every test user can read (a checkout under a home directory may not be).
rm -rf /opt/mip && cp -r "$1" /opt/mip && chmod -R a+rX /opt/mip
fail() { echo "FAIL: $*"; exit 1; }
# login USER CMD — a login shell for USER. The CI runner's /etc/environment
# sets XDG_CONFIG_HOME to the runner account's folder (runner-images
# configure-environment.sh), which no test user can write; drop it.
login() { su - "$1" -c "unset XDG_CONFIG_HOME; $2"; }
as() { login "$1" "umask 077; $2"; }
for u in alice bob carol dave; do useradd -m "$u"; done
mkdir -p /srv/locked && chmod 700 /srv/locked

bash /opt/mip/admin/share-hf-cache.sh /srv/locked/hub
bash /opt/mip/admin/share-hf-cache.sh --check /srv/locked/hub || fail "--check fails after sharing"
as alice 'mkdir -p "$HF_HUB_CACHE/models--x/refs" "$HF_HUB_CACHE/models--x/blobs" && echo a >"$HF_HUB_CACHE/models--x/refs/main"' \
  || fail "alice cannot write the cache"
as bob 'echo b >"$HF_HUB_CACHE/models--x/refs/main" && touch "$HF_HUB_CACHE/models--x/blobs/g"' \
  || fail "bob cannot update what alice created (both umask 077)"
as carol 'mv "$HF_HUB_CACHE/models--x/refs/main" "$HF_HUB_CACHE/models--x/refs/old"' || fail "carol cannot replace an entry"
[ "$(as alice 'echo $HF_HUB_CACHE')" = /srv/locked/hub ] || fail "HF_HUB_CACHE missing from a login shell"
chmod 444 /srv/locked/hub/models--x/blobs/g
bash /opt/mip/admin/share-hf-cache.sh /srv/locked/hub >/dev/null
[ "$(grep -c '^HF_HUB_CACHE=' /etc/environment)" = 1 ] || fail "re-run stacked /etc/environment"
[ "$(stat -c %a /srv/locked/hub/models--x/blobs/g)" = 444 ] || fail "a re-run made a blob writable"
bash /opt/mip/admin/share-hf-cache.sh relative 2>/dev/null && fail "a relative DIR was accepted"

# The hf-cache Step, as a user, no sudo: dave creates and shares /srv/team/hub.
mkdir -p /srv/team && chmod 1777 /srv/team
cfg='HF_HUB_CACHE_DIR=/srv/team/hub HF_HUB_CACHE_SHARED=yes'
login dave "$cfg /opt/mip/init.sh run hf-cache </dev/null" >/tmp/run.out 2>&1 || { cat /tmp/run.out /home/dave/.local/state/my-init-pipeline/runs/latest/*.log; fail "hf-cache run failed"; }
grep -q 'hf-cache *ran' /tmp/run.out || { cat /tmp/run.out; fail "hf-cache did not run"; }
login dave "$cfg bash /opt/mip/lib/step.sh /opt/mip/actions/hf-cache.sh check" || fail "hf-cache Check fails after sharing"
as dave 'mkdir -p /srv/team/hub/models--y && echo d >/srv/team/hub/models--y/f'
as carol 'echo c >>/srv/team/hub/models--y/f && mkdir /srv/team/hub/models--y/sub' || fail "another user cannot write the shared cache"

# The optional hf-export Step, named (tests/runner.bats covers skipping it when
# not chosen). dave has passwordless sudo, so it needs no terminal.
command -v sudo >/dev/null || { apt-get install -y -qq sudo >/dev/null 2>&1 || apt-get update -qq && apt-get install -y -qq sudo >/dev/null; }
echo 'dave ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/dave
# hf-export always takes the terminal: give it one (util-linux script).
login dave "script -qec '/opt/mip/init.sh run hf-export' /dev/null" >/tmp/run.out 2>&1 \
  || { cat /tmp/run.out /home/dave/.local/state/my-init-pipeline/runs/latest/*.log; fail "hf-export run failed"; }
grep -q 'hf-export *ran' /tmp/run.out || { cat /tmp/run.out; fail "hf-export did not run"; }
[ "$(login carol 'echo $HF_HUB_CACHE')" = /srv/team/hub ] || fail "a new login does not get the exported HF_HUB_CACHE"
/opt/mip/init.sh run -y >/tmp/root.out 2>&1 && fail "init.sh ran as root"
grep -q "don't run my-init-pipeline as root" /tmp/root.out || { cat /tmp/root.out; fail "no root refusal message"; }
echo "admin: ok"
