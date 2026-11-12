#!/usr/bin/env bats
# What a cache folder is, as admin/share-hf-cache.sh reports it (docs/adr/0003):
# the queries the hf-cache and hf-export Steps ask. What needs root (sharing
# other users' entries, the real /etc export) is in tests/share-root.sh.

load helpers

setup() { setup_pipeline; }

admin() { bash "$ROOT/admin/share-hf-cache.sh" "$@"; }

# state_is DIR KEY=VALUE... — --state DIR has each of those lines.
state_is() {
  local dir="$1" out want
  out="$(admin --state "$dir")"
  for want in "${@:2}"; do
    grep -qxF -- "$want" <<<"$out" || { echo "--state $dir lacks $want:"; echo "$out"; return 1; }
  done
}

@test "--state: the folder as a cache folder — trailing / dropped, ~ expanded, its two caches named" {
  state_is "$T/f/" "folder=$T/f" "HF_HUB_CACHE=$T/f/hub" "HF_DATASETS_CACHE=$T/f/datasets"
  state_is '~/hf/' "folder=$HOME/hf" home=yes
  state_is "$HOME" home=yes
  state_is "$T/f" home=no
}

@test "--state: a path that cannot be a cache folder exits 1 and says why" {
  local bad
  for bad in rel/hf / "" ./x; do
    run admin --state "$bad"
    [ "$status" -eq 1 ] && [[ "$output" == *"absolute path other than /"* ]]
  done
  run admin "$T/f" extra
  [ "$status" -eq 2 ]
  run admin --check "$T/f"                   # the flags --state replaced are gone
  [ "$status" -eq 2 ]
}

@test "--state: owner and writable follow the folder as it is on disk" {
  state_is "$T/new" owner=none writable=no shared=none exported=no
  mkdir -p "$T/f/hub"
  state_is "$T/f" owner=me writable=no     # datasets/ is missing
  mkdir "$T/f/datasets"
  state_is "$T/f" owner=me writable=yes
  chmod 555 "$T/f/datasets"
  state_is "$T/f" writable=no
  chmod 755 "$T/f/datasets"
  if [ "$(id -u)" != 0 ]; then state_is /usr owner=other writable=no; fi
}

@test "--state: shared is group for a setgid group-writable folder, acl once the script shared it, else none" {
  mkdir -p "$T/g" "$T/p"
  chmod 2775 "$T/g"
  state_is "$T/g" shared=group
  chmod 2755 "$T/g"
  state_is "$T/g" shared=none               # the group cannot write
  state_is "$T/p" shared=none
  command -v setfacl >/dev/null || skip "setfacl (acl) not installed"
  admin "$T/p" >/dev/null
  state_is "$T/p" shared=acl owner=me writable=yes
  state_is "$T/p/hub" shared=acl             # handed down to what it holds
  setfacl -b "$T/p"
  state_is "$T/p" shared=none
}

@test "--state: exported only when the login profile and /etc/environment both carry the folder" {
  export_for_everyone "$T/sys"
  state_is "$T/sys" exported=yes
  state_is "$T/other" exported=no
  [ "$(admin --exported-folder)" = "$T/sys" ]
  : >"$MIP_HF_ENVIRONMENT"
  state_is "$T/sys" exported=no             # a login shell has it; pam_env sessions do not
  rm "$MIP_HF_PROFILE"
  [ -z "$(admin --exported-folder)" ]
}

@test "--folder-of: the folder whose hub/ and datasets/ these are, or nothing" {
  [ "$(admin --folder-of /d/hf/hub /d/hf/datasets)" = /d/hf ]
  [ "$(admin --folder-of /d/hf/hub)" = /d/hf ]
  [ -z "$(admin --folder-of /d/hf/hub /e/datasets)" ]
  [ -z "$(admin --folder-of /d/hf/hub "")" ]
  [ -z "$(admin --folder-of /d/hf/models)" ]
  [ "$(admin --folder-of /d/hf//hub)" = /d/hf ]          # printed as a cache folder
  [ -z "$(admin --folder-of /hub)" ]                     # / cannot be one
}
