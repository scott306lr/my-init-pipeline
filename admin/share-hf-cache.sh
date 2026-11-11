#!/usr/bin/env bash
# Share a Hugging Face hub cache with every user of this server: no group, no
# re-login, nothing to do to add a user.
#
#   admin/share-hf-cache.sh DIR           share DIR (as its owner, or as root)
#   admin/share-hf-cache.sh --check DIR   exit 0 if DIR is shared
#   curl -fsSL https://raw.githubusercontent.com/scott306lr/my-init-pipeline/main/admin/share-hf-cache.sh | sudo bash -s -- DIR
#
# As DIR's owner (the hf-cache Step runs it so): creates DIR if missing and lets
# every user read, add and replace entries in it, through a default ACL that
# keeps new entries that way whoever creates them, whatever their umask. Files
# under blobs/ keep the read-only mode Hugging Face gives its immutable payloads.
# As root it also covers entries other users own, installs acl (setfacl) with
# apt if missing, lets everyone into a parent they cannot enter, and exports
# HF_HUB_CACHE for every user (/etc/profile.d, /etc/environment), so users who
# do not run my-init-pipeline use it too. A DIR it creates belongs to the user
# who ran sudo. Safe to re-run. HF_HOME, which holds each user's token, is
# never shared.
#
# Any user can then change any cached file, including model code that
# trust_remote_code runs: share only on a server whose users you trust.
set -euo pipefail

# Everything lives in main, called on the last line: a truncated download
# defines a function that is never called instead of running half a script.
main() {
  local check=0 root=0 dir p
  if [ "${1:-}" = --check ]; then check=1; shift; fi
  if [ $# -ne 1 ]; then
    echo "usage: share-hf-cache.sh [--check] DIR" >&2
    exit 2
  fi
  dir="${1%/}"
  case "$dir" in /?*) ;; *) die "DIR must be an absolute path: $dir" ;; esac
  if [ "$check" = 1 ]; then is_shared "$dir"; return; fi
  if [ "$(id -u)" = 0 ]; then root=1; fi

  if [ "$root" = 1 ]; then
    ensure_setfacl
  elif ! command -v setfacl >/dev/null; then
    die "setfacl not found (package acl); ask root to run: sudo bash $0 $dir"
  fi
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    if [ "$root" = 1 ] && [ -n "${SUDO_USER:-}" ]; then chown "$SUDO_USER" "$dir"; fi
  fi
  if [ "$root" = 0 ] && [ ! -O "$dir" ]; then
    die "$dir belongs to $(stat -c %U "$dir"); ask them, or root, to run: share-hf-cache.sh $dir"
  fi

  # Root covers every entry; an owner, the entries it owns.
  local -a mine=()
  if [ "$root" = 0 ]; then mine=(-user "$(id -u)"); fi
  find "$dir" "${mine[@]}" -type d -exec setfacl -m o::rwx -d -m u::rwx,g::rwx,o::rwx {} +
  find "$dir" "${mine[@]}" -type f ! -path '*/blobs/*' -exec setfacl -m o::rw {} +

  # A parent others cannot enter (a home directory, a 700 folder) hides DIR.
  p="${dir%/*}"
  while [ -n "$p" ]; do
    if [ "$(stat -c %A "$p" | cut -c 10)" = - ] || [ "$(stat -c %A "$p" | cut -c 10)" = T ]; then
      if [ "$root" = 1 ] || [ -O "$p" ]; then
        chmod o+x "$p"
        echo "let everyone through $p"
      else
        echo "warning: other users cannot enter $p; ask root to run this script" >&2
      fi
    fi
    p="${p%/*}"
  done

  if [ "$root" = 1 ]; then
    printf 'export HF_HUB_CACHE=%q\n' "$dir" >/etc/profile.d/hf-hub-cache.sh
    chmod 644 /etc/profile.d/hf-hub-cache.sh
    sed -i '/^HF_HUB_CACHE=/d' /etc/environment
    printf 'HF_HUB_CACHE=%s\n' "$dir" >>/etc/environment
    echo "HF_HUB_CACHE=$dir for every user from their next login"
  fi
  echo "$dir is shared with every user of this server"
}

# is_shared DIR — everyone may add entries to DIR, and so may they to new subdirectories.
is_shared() {
  local acl
  [ -d "$1" ] && acl="$(getfacl -p "$1" 2>/dev/null)" || return 1
  grep -qx 'other::rwx' <<<"$acl" && grep -qx 'default:other::rwx' <<<"$acl"
}

die() { echo "error: $*" >&2; exit 1; }

ensure_setfacl() {
  command -v setfacl >/dev/null && return 0
  command -v apt-get >/dev/null || die "setfacl not found; install your distribution's acl package"
  echo "installing acl (for setfacl)"
  apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq acl >/dev/null
}

main "$@"
