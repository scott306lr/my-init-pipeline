#!/usr/bin/env bash
# One-time root setup for a Hugging Face hub cache shared by several users: the
# part of sharing the per-user Pipeline (no root) cannot do. Run it on each new
# server, from a clone or straight from GitHub:
#
#   sudo admin/share-hf-cache.sh DIR GROUP [USER...]
#   curl -fsSL https://raw.githubusercontent.com/scott306lr/my-init-pipeline/main/admin/share-hf-cache.sh | sudo bash -s -- DIR GROUP [USER...]
#
# Creates GROUP and adds each USER; makes DIR group-writable with the setgid bit
# (new entries inherit GROUP) and a default ACL (new entries stay group-writable
# whatever each user's umask); lets GROUP traverse every parent of DIR that
# others cannot; and exports HF_HUB_CACHE=DIR for every user's login shells
# (/etc/profile.d) and sessions (/etc/environment). Files keep their owners.
# Installs the acl package (setfacl) with apt if it is missing. Safe to re-run,
# e.g. to add a user. Credentials are not shared: HF_HOME, which holds each
# user's token, stays at its per-user default. Users pick up the group and the
# variable at their next login.
set -euo pipefail

# Everything lives in main, called on the last line: a truncated download
# defines a function that is never called instead of running half a script.
main() {
  if [ $# -lt 2 ]; then
    echo "usage: share-hf-cache.sh DIR GROUP [USER...]   (as root)" >&2
    exit 2
  fi
  [ "$(id -u)" = 0 ] || die "run as root (sudo)"
  local dir="${1%/}" group="$2" u p
  shift 2
  case "$dir" in /?*) ;; *) die "DIR must be an absolute path: $dir" ;; esac

  ensure_setfacl
  getent group "$group" >/dev/null || groupadd "$group"
  for u in "$@"; do usermod -aG "$group" "$u"; done

  mkdir -p "$dir"
  chgrp -R "$group" "$dir"
  chmod -R o-w "$dir"
  find "$dir" -type d -exec chmod u+rwx,g+rwxs {} +
  find "$dir" -type f -exec chmod g+rw {} +
  setfacl -R -m "g:$group:rwX" -d -m "u::rwX,g::rwX,g:$group:rwX,o::rX" "$dir"

  # A parent others cannot enter (a home directory, a 700 folder) hides DIR.
  p="${dir%/*}"
  while [ -n "$p" ]; do
    if [ "$(stat -c %A "$p" | cut -c 10)" != x ] && [ "$(stat -c %A "$p" | cut -c 10)" != t ]; then
      setfacl -m "g:$group:--x" "$p"
      echo "let $group traverse $p"
    fi
    p="${p%/*}"
  done

  printf 'export HF_HUB_CACHE=%q\n' "$dir" >/etc/profile.d/hf-hub-cache.sh
  chmod 644 /etc/profile.d/hf-hub-cache.sh
  sed -i '/^HF_HUB_CACHE=/d' /etc/environment
  printf 'HF_HUB_CACHE=%s\n' "$dir" >>/etc/environment

  ls -ld "$dir"
  echo "HF_HUB_CACHE=$dir for every user from their next login; members of $group: $(getent group "$group" | cut -d: -f4)"
  echo "Users of my-init-pipeline: log in again, then run it; the hf-cache Step offers $dir as the default."
}

die() { echo "error: $*" >&2; exit 1; }

ensure_setfacl() {
  command -v setfacl >/dev/null && return 0
  command -v apt-get >/dev/null || die "setfacl not found; install your distribution's acl package"
  echo "installing acl (for setfacl)"
  apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq acl >/dev/null
}

main "$@"
