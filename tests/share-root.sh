#!/usr/bin/env bash
# Sharing the hub cache with every user, as root on a throwaway machine (it adds
# users and writes /etc/profile.d): run by tests/admin.sh, in ubuntu:22.04
# locally and directly on the CI runner.
#   - root runs admin/share-hf-cache.sh on a cache folder: users with umask 077
#     add, update and replace each other's entries in hub/ and datasets/
#     through a 700 parent, a login shell carries HF_HUB_CACHE and
#     HF_DATASETS_CACHE, the old export file goes, a re-run stacks nothing and
#     leaves blobs read-only;
#   - a user runs the hf-cache Step on a folder they create: it is shared
#     without sudo, their private downloads move in and are writable by
#     others, and a user who never ran anything can write to it;
#   - the optional hf-export Step, named, makes that folder every user's cache
#     with sudo;
#   - init.sh refuses root on a real machine, not in a container.
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

echo 'export HF_HUB_CACHE=/old' >/etc/profile.d/hf-hub-cache.sh   # the export's name before datasets/
bash /opt/mip/admin/share-hf-cache.sh /srv/locked/hf
bash /opt/mip/admin/share-hf-cache.sh --check /srv/locked/hf || fail "--check fails after sharing"
[ ! -e /etc/profile.d/hf-hub-cache.sh ] || fail "the old export file was left behind"
as alice 'mkdir -p "$HF_HUB_CACHE/models--x/refs" "$HF_HUB_CACHE/models--x/blobs" && echo a >"$HF_HUB_CACHE/models--x/refs/main"' \
  || fail "alice cannot write the cache"
as bob 'echo b >"$HF_HUB_CACHE/models--x/refs/main" && touch "$HF_HUB_CACHE/models--x/blobs/g"' \
  || fail "bob cannot update what alice created (both umask 077)"
as carol 'mv "$HF_HUB_CACHE/models--x/refs/main" "$HF_HUB_CACHE/models--x/refs/old"' || fail "carol cannot replace an entry"
[ "$(as alice 'echo $HF_HUB_CACHE $HF_DATASETS_CACHE')" = "/srv/locked/hf/hub /srv/locked/hf/datasets" ] \
  || fail "HF_HUB_CACHE / HF_DATASETS_CACHE missing from a login shell"
as alice 'mkdir -p "$HF_DATASETS_CACHE/ds___y" && echo a >"$HF_DATASETS_CACHE/ds___y/data.arrow"' || fail "alice cannot write the datasets cache"
as bob 'echo b >>"$HF_DATASETS_CACHE/ds___y/data.arrow"' || fail "bob cannot update alice's datasets cache entry"
chmod 444 /srv/locked/hf/hub/models--x/blobs/g
bash /opt/mip/admin/share-hf-cache.sh /srv/locked/hf >/dev/null
if [ "$(grep -c '^HF_HUB_CACHE=' /etc/environment)" != 1 ] || [ "$(grep -c '^HF_DATASETS_CACHE=' /etc/environment)" != 1 ]; then
  fail "re-run stacked /etc/environment"
fi
[ "$(stat -c %a /srv/locked/hf/hub/models--x/blobs/g)" = 444 ] || fail "a re-run made a blob writable"
bash /opt/mip/admin/share-hf-cache.sh relative 2>/dev/null && fail "a relative DIR was accepted"

# The hf-cache Step, as a user, no sudo: dave creates and shares /srv/team/hf,
# moving his private downloads into it.
mkdir -p /srv/team && chmod 1777 /srv/team
cfg='HF_CACHE_DIR=/srv/team/hf HF_CACHE_SHARED=yes'
as dave 'mkdir -p ~/.cache/huggingface/hub/models--z ~/.cache/huggingface/datasets/ds___z && echo z >~/.cache/huggingface/hub/models--z/f && echo z >~/.cache/huggingface/datasets/ds___z/f'
login dave "$cfg /opt/mip/init.sh run hf-cache </dev/null" >/tmp/run.out 2>&1 || { cat /tmp/run.out /home/dave/.local/state/my-init-pipeline/runs/latest/*.log; fail "hf-cache run failed"; }
grep -q 'hf-cache *ran' /tmp/run.out || { cat /tmp/run.out; fail "hf-cache did not run"; }
login dave "$cfg bash /opt/mip/lib/step.sh /opt/mip/actions/hf-cache.sh check" || fail "hf-cache Check fails after sharing"
as dave 'mkdir -p /srv/team/hf/hub/models--y && echo d >/srv/team/hf/hub/models--y/f'
as carol 'echo c >>/srv/team/hf/hub/models--y/f && mkdir /srv/team/hf/hub/models--y/sub' || fail "another user cannot write the shared cache"
as carol 'echo c >>/srv/team/hf/hub/models--z/f && echo c >>/srv/team/hf/datasets/ds___z/f' || fail "dave's moved downloads are not writable by others"
[ ! -e /home/dave/.cache/huggingface/hub/models--z ] || fail "dave's downloads were not moved"

# A folder someone else shares through a setgid group, as an admin might have
# set it up (spark1): a member uses it as it is (no question, no share script)
# and their moved downloads join the group, so other members can update them.
useradd -m erin; groupadd team; usermod -aG team erin; usermod -aG team carol
mkdir -p /srv/grp/hf/hub /srv/grp/hf/datasets && chgrp -R team /srv/grp && chmod -R 2775 /srv/grp
as erin 'mkdir -p ~/.cache/huggingface/datasets/ds___g && echo g >~/.cache/huggingface/datasets/ds___g/f'
login erin "HF_CACHE_DIR=/srv/grp/hf /opt/mip/init.sh run hf-cache </dev/null" >/tmp/run.out 2>&1 \
  || { cat /tmp/run.out /home/erin/.local/state/my-init-pipeline/runs/latest/*.log; fail "hf-cache failed on a group-shared folder"; }
grep -q 'hf-cache *ran' /tmp/run.out || { cat /tmp/run.out; fail "hf-cache did not run on a group-shared folder"; }
[ "$(stat -c %G /srv/grp/hf/datasets/ds___g/f)" = team ] || fail "moved download did not join the folder's group"
as carol 'echo c >>/srv/grp/hf/datasets/ds___g/f' || {
  ls -la /srv/grp/hf/datasets /srv/grp/hf/datasets/ds___g; getfacl -p /srv/grp/hf/datasets/ds___g; id carol; su - carol -c id
  cat /home/erin/.local/state/my-init-pipeline/runs/latest/hf-cache.log
  fail "another member cannot update a moved download"
}
getfacl -p /srv/grp/hf | grep -q '^default:' && fail "a folder someone else owns got an ACL"
# Leaving it again: other members' downloads stay.
as carol 'mkdir -p /srv/grp/hf/hub/models--c && echo c >/srv/grp/hf/hub/models--c/f'
login erin "HF_CACHE_DIR=/home/erin/hf /opt/mip/init.sh run hf-cache </dev/null" >/tmp/run.out 2>&1 \
  || { cat /tmp/run.out; fail "could not point erin at a private folder"; }
[ -e /srv/grp/hf/hub/models--c/f ] || fail "leaving a group-shared folder took another member's downloads"

# The optional hf-export Step, named (tests/runner.bats covers skipping it when
# not chosen). dave has passwordless sudo, so it runs without a terminal.
command -v sudo >/dev/null || { apt-get install -y -qq sudo >/dev/null 2>&1 || apt-get update -qq && apt-get install -y -qq sudo >/dev/null; }
echo 'dave ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/dave
login dave "/opt/mip/init.sh run hf-export </dev/null" >/tmp/run.out 2>&1 \
  || { cat /tmp/run.out /home/dave/.local/state/my-init-pipeline/runs/latest/*.log; fail "hf-export run failed"; }
grep -q 'hf-export *ran' /tmp/run.out || { cat /tmp/run.out; fail "hf-export did not run"; }
[ "$(login carol 'echo $HF_HUB_CACHE $HF_DATASETS_CACHE')" = "/srv/team/hf/hub /srv/team/hf/datasets" ] \
  || fail "a new login does not get the exported cache folder"
# Root: refused on a real machine, allowed in a container or CI job. An unknown
# Step name shows which: the refusal comes before the Pipeline is read.
/opt/mip/init.sh run no-such-step >/tmp/root.out 2>&1 && fail "init.sh accepted an unknown Step"
# shellcheck source=lib/common.sh
if ! (. /opt/mip/lib/common.sh && root_outside_container); then
  grep -q "unknown step" /tmp/root.out || { cat /tmp/root.out; fail "root was refused in a container"; }
else
  grep -q "don't run my-init-pipeline as root" /tmp/root.out || { cat /tmp/root.out; fail "root was not refused"; }
fi
echo "admin: ok"
