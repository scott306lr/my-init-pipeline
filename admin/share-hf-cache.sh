#!/usr/bin/env bash
# Share a Hugging Face cache folder with every user of this server: no group,
# no re-login, nothing to do to add a user. The folder holds hub/ (Hub
# downloads: models and datasets) and datasets/ (the datasets library's Arrow
# cache), as HF_HOME would, but never the login token.
#
#   admin/share-hf-cache.sh DIR             share DIR (as its owner, or as root)
#   curl -fsSL https://raw.githubusercontent.com/scott306lr/my-init-pipeline/main/admin/share-hf-cache.sh | sudo bash -s -- DIR
#
# This script owns what a cache folder is (docs/adr/0003): its layout, which
# paths are valid, and whether it is shared or exported. The hf-cache and
# hf-export Steps ask it, as the caller, without changing anything:
#
#   admin/share-hf-cache.sh --state DIR     print DIR's state, one key=value per line:
#                                             folder=DIR as a cache folder: ~ expanded, no trailing /
#                                             HF_HUB_CACHE=, HF_DATASETS_CACHE=
#                                                                      the caches in it, each under
#                                                                      the variable that points to it
#                                             home=yes|no              DIR is, or lies in, your home
#                                             owner=me|other|none      none: DIR does not exist
#                                             shared=acl|group|none    how others may add entries
#                                             writable=yes|no          you can write every cache
#                                             exported=yes|no          the login profile and
#                                                                      /etc/environment both carry it
#                                           home, owner and shared hold for any directory, so the
#                                           Steps also ask them about one cache on its own.
#   admin/share-hf-cache.sh --folder-of HUB [DATASETS]
#                                           print the cache folder whose hub/ is HUB (and whose
#                                           datasets/ is DATASETS, when given); nothing if none
#   admin/share-hf-cache.sh --exported-folder
#                                           print the folder login shells get, if any. It reads
#                                           the login profile alone, so a half-written export
#                                           still names its folder, whose state then says
#                                           exported=no and a re-run as root repairs.
#
# DIR must be an absolute path other than /; anything else exits 1.
#
# As DIR's owner (the hf-cache Step runs it so): creates DIR, DIR/hub and
# DIR/datasets if missing, and lets every user read, add and replace entries,
# through a default ACL that keeps new entries that way whoever creates them,
# whatever their umask. Files under blobs/ keep the read-only mode Hugging Face
# gives its immutable payloads. In a DIR already shared it covers just your own
# entries (say, downloads you moved in), following how DIR is shared: its ACL,
# or its setgid group (your entries join the group and lose any ACL they brought,
# as if created there). As root it
# also covers entries other users own, installs acl (setfacl) with apt if
# missing, lets everyone into a parent they cannot enter, and exports
# HF_HUB_CACHE=DIR/hub and HF_DATASETS_CACHE=DIR/datasets for every user
# (/etc/profile.d/hf-cache.sh, /etc/environment), so users who do not run
# my-init-pipeline use it too. A DIR it creates belongs to the user who ran
# sudo. Safe to re-run. HF_HOME, which holds each user's token, is never shared.
#
# Any user can then change any cached file, including model code that
# trust_remote_code runs: share only on a server whose users you trust.
set -euo pipefail

# Everything lives in main, called on the last line: a truncated download
# defines a function that is never called instead of running half a script.
main() {
  local root=0 dir p line
  # Where an export for every user lives: login shells read PROFILE, and
  # pam_env reads ENVIRONMENT for sessions that start no login shell.
  PROFILE="${MIP_HF_PROFILE:-/etc/profile.d/hf-cache.sh}"       # override: tests
  ENVIRONMENT="${MIP_HF_ENVIRONMENT:-/etc/environment}"         # override: tests
  case "${1:-}" in
    --exported-folder) [ $# -eq 1 ] || usage; exported_folder; return ;;
    --folder-of) [ $# -eq 2 ] || [ $# -eq 3 ] || usage; folder_of "${@:2}"; return ;;
    --state) [ $# -eq 2 ] || usage; dir="$(cache_folder "$2")"; state "$dir"; return ;;
    -*) usage ;;
  esac
  [ $# -eq 1 ] || usage
  dir="$(cache_folder "$1")"
  if [ "$(id -u)" = 0 ]; then root=1; fi

  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    if [ "$root" = 1 ] && [ -n "${SUDO_USER:-}" ]; then chown "$SUDO_USER" "$dir"; fi
  fi
  if [ "$root" = 0 ] && [ ! -O "$dir" ] && [ "$(how_shared "$dir")" = none ]; then
    die "$dir belongs to $(stat -c %U "$dir"); ask them, or root, to run: share-hf-cache.sh $dir"
  fi
  while IFS='=' read -r _ p; do
    if [ ! -d "$p" ]; then
      mkdir "$p"
      if [ "$root" = 1 ] && [ -n "${SUDO_USER:-}" ]; then chown "$SUDO_USER" "$p"; fi
    fi
  done < <(cache_vars "$dir")

  # A folder shared through its group stays so: your entries join the group.
  if [ "$root" = 0 ] && [ "$(how_shared "$dir")" = group ]; then
    join_group "$dir"
    echo "$dir is shared through group $(stat -c %G "$dir"); your entries in it now are too"
    return
  fi

  if [ "$root" = 1 ]; then
    ensure_setfacl
  elif ! command -v setfacl >/dev/null; then
    die "setfacl not found (package acl); ask root to run: sudo bash $0 $dir"
  fi
  # Root covers every entry; anyone else, the entries they own.
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
    profile_lines "$dir" >"$PROFILE"
    chmod 644 "$PROFILE"
    rm -f /etc/profile.d/hf-hub-cache.sh   # its name before datasets/ was shared too
    while IFS= read -r line; do sed -i "/^${line%%=*}=/d" "$ENVIRONMENT"; done < <(cache_vars "$dir")
    cache_vars "$dir" >>"$ENVIRONMENT"
    echo "$(cache_vars "$dir" | paste -sd ' ') for every user from their next login"
  fi
  echo "$dir is shared with every user of this server"
  if [ "$root" = 0 ] && ! is_exported "$dir"; then
    echo "For users who don't run my-init-pipeline, root can export it for everyone: sudo bash $0 $dir"
  fi
}

# how_shared DIR — how DIR lets other users add entries: acl (everyone, and
# new subdirectories too, by its default ACL), group (it hands its group down
# with the setgid bit and the group may write), or none.
how_shared() {
  local acl
  if [ -d "$1" ] && acl="$(getfacl -p "$1" 2>/dev/null)" &&
    grep -qx 'other::rwx' <<<"$acl" && grep -qx 'default:other::rwx' <<<"$acl"; then
    echo acl
  elif [ -d "$1" ] && [ -g "$1" ] && [ "$(stat -c %A "$1" | cut -c 6)" = w ]; then
    echo group
  else
    echo none
  fi
}

# join_group DIR — give your entries in a group-shared DIR its group and group
# write, and drop any ACL they brought along (from a home with a default ACL,
# where `chmod g+…` would move only the mask), as if they had been created
# there. Blob payloads stay read-only.
join_group() {
  local dir="$1" grp me
  grp="$(stat -c %G "$dir")" me="$(id -u)"
  if command -v setfacl >/dev/null && [ -z "$(getfacl -p --skip-base "$dir" 2>/dev/null)" ]; then
    find "$dir" -user "$me" ! -type l -exec setfacl -b {} +
  fi
  find "$dir" -user "$me" ! -group "$grp" -exec chgrp -h "$grp" {} +
  find "$dir" -user "$me" -type d -exec chmod g+rwxs {} +
  find "$dir" -user "$me" -type f ! -path '*/blobs/*' -exec chmod g+rw {} +
}

# cache_vars DIR — the caches of cache folder DIR, one VARIABLE=PATH per line:
# the variable Hugging Face reads, and where in DIR it points. With folder_of,
# its inverse, this is the one place the layout is written down.
cache_vars() { printf 'HF_HUB_CACHE=%s\nHF_DATASETS_CACHE=%s\n' "$1/hub" "$1/datasets"; }

# folder_of HUB [DATASETS] — the cache folder holding them, when HUB is
# <folder>/hub and DATASETS (if given) is <folder>/datasets; else nothing.
folder_of() {
  case "$1" in */hub) ;; *) return 0 ;; esac
  if [ $# -eq 1 ] || [ "$2" = "${1%/hub}/datasets" ]; then as_cache_folder "${1%/hub}" || true; fi
}

# as_cache_folder PATH — PATH as a cache folder: ~ expanded, no trailing /.
# Status 1, printing nothing, unless that is an absolute path other than /.
as_cache_folder() {
  local f="${1/#\~/$HOME}"
  f="${f%/}"
  case "$f" in /?*) printf '%s\n' "$f" ;; *) return 1 ;; esac
}

# cache_folder PATH — as_cache_folder, or die saying what a cache folder must be.
cache_folder() {
  as_cache_folder "$1" || die "the cache folder must be an absolute path other than /: ${1:-<empty>}"
}

# state DIR — the --state lines for cache folder DIR (see the top of this file).
state() {
  local dir="$1" home=no owner=none writable=yes exported=no p
  if [[ "$(realpath -m "$dir")/" == "$(realpath -m "$HOME")/"* ]]; then home=yes; fi
  if [ -e "$dir" ]; then
    if [ -O "$dir" ]; then owner=me; else owner=other; fi
  fi
  while IFS='=' read -r _ p; do
    if [ ! -w "$p" ]; then writable=no; fi
  done < <(cache_vars "$dir")
  if is_exported "$dir"; then exported=yes; fi
  printf 'folder=%s\n' "$dir"
  cache_vars "$dir"
  printf 'home=%s\nowner=%s\nshared=%s\nwritable=%s\nexported=%s\n' \
    "$home" "$owner" "$(how_shared "$dir")" "$writable" "$exported"
}

# exported_folder — the folder whose caches PROFILE exports, or nothing.
exported_folder() {
  [ -f "$PROFILE" ] || return 0
  (
    # shellcheck disable=SC1090
    . "$PROFILE"
    if [ -n "${HF_HUB_CACHE:-}" ]; then folder_of "$HF_HUB_CACHE" "${HF_DATASETS_CACHE:-}"; fi
  )
}

# is_exported DIR — both PROFILE and ENVIRONMENT export DIR's caches.
is_exported() {
  local line
  [ "$(cat "$PROFILE" 2>/dev/null)" = "$(profile_lines "$1")" ] || return 1
  while IFS= read -r line; do
    grep -qxF -- "$line" "$ENVIRONMENT" 2>/dev/null || return 1
  done < <(cache_vars "$1")
}

# profile_lines DIR — what PROFILE holds once DIR is exported.
profile_lines() {
  local var path
  while IFS='=' read -r var path; do printf 'export %s=%q\n' "$var" "$path"; done < <(cache_vars "$1")
}

usage() {
  echo "usage: share-hf-cache.sh DIR | --state DIR | --folder-of HUB [DATASETS] | --exported-folder" >&2
  exit 2
}

die() { echo "error: $*" >&2; exit 1; }

ensure_setfacl() {
  command -v setfacl >/dev/null && return 0
  command -v apt-get >/dev/null || die "setfacl not found; install your distribution's acl package"
  echo "installing acl (for setfacl)"
  apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq acl >/dev/null
}

main "$@"
