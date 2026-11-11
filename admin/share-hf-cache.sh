#!/usr/bin/env bash
# One-time root setup for a Hugging Face hub cache shared by several users: the
# only part of sharing the per-user Pipeline (no root) cannot do.
#
#   sudo admin/share-hf-cache.sh DIR GROUP [USER...]
#
# Creates GROUP and adds each USER, makes DIR group-writable with the setgid bit
# (new entries inherit GROUP) and a default ACL (new entries are group-writable
# whatever each user's umask), and exports HF_HUB_CACHE=DIR for every user's
# login shells (/etc/profile.d) and sessions (/etc/environment). Files keep
# their owners. Safe to re-run, e.g. to add a user. Credentials are not shared:
# HF_HOME, which holds each user's token, stays at its per-user default.
# Users pick up the group and variable at their next login.
set -euo pipefail

usage() { sed -n 's/^#   //p' "$0" >&2; exit 2; }
[ $# -ge 2 ] || usage
[ "$(id -u)" = 0 ] || { echo "error: run as root (sudo)" >&2; exit 1; }
dir="${1%/}" group="$2"
shift 2
case "$dir" in /?*) ;; *) echo "error: DIR must be an absolute path: $dir" >&2; exit 1 ;; esac

getent group "$group" >/dev/null || groupadd "$group"
for u in "$@"; do usermod -aG "$group" "$u"; done

mkdir -p "$dir"
chgrp -R "$group" "$dir"
chmod -R o-w "$dir"
find "$dir" -type d -exec chmod u+rwx,g+rwxs {} +
find "$dir" -type f -exec chmod g+rw {} +
setfacl -R -m "g:$group:rwX" -d -m "u::rwX,g::rwX,g:$group:rwX,o::rX" "$dir"

printf 'export HF_HUB_CACHE=%q\n' "$dir" >/etc/profile.d/hf-hub-cache.sh
chmod 644 /etc/profile.d/hf-hub-cache.sh
sed -i '/^HF_HUB_CACHE=/d' /etc/environment
printf 'HF_HUB_CACHE=%s\n' "$dir" >>/etc/environment

ls -ld "$dir"
getfacl -p "$dir"
echo "HF_HUB_CACHE=$dir for every user from their next login; members of $group: $(getent group "$group" | cut -d: -f4)"
