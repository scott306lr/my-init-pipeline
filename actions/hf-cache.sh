# summary: Export HF_HUB_CACHE (Hugging Face model and dataset downloads): HF_HUB_CACHE_DIR from config.sh, else asked on the terminal
# check:   env.sh exports HF_HUB_CACHE (equal to HF_HUB_CACHE_DIR when set) and you can write to it (and it is shared, when HF_HUB_CACHE_SHARED=yes); HF_HOME is not exported and ~/.cache/huggingface is a real directory
# interactive: yes
# notes:   Only the hub cache is relocated. HF_HOME stays at its default,
#          ~/.cache/huggingface, so the login token (and other per-user state)
#          never lands on a shared or big disk. The Run asks for the directory,
#          defaulting to the HF_HUB_CACHE already in effect (recorded here, or
#          exported system-wide), unless HF_HUB_CACHE_DIR is set. For a
#          directory outside your home that is not shared yet, it also asks
#          whether to share it with every user of the server, unless
#          HF_HUB_CACHE_SHARED (yes/no) answers; sharing runs
#          admin/share-hf-cache.sh as you, no sudo. With both answered the Step
#          runs without a terminal. Re-pointing does not move existing
#          downloads (they are re-fetched on use). An HF_HOME export or ~/.cache/huggingface symlink
#          left by the former hf-home Step is undone: the entries you own at its
#          target, except hub/, move back into a real ~/.cache/huggingface, and
#          that hub/ becomes the prompt's default.

HF_HOME_DEFAULT="$HOME/.cache/huggingface"

interactive() {
  [ -z "$HF_HUB_CACHE_DIR" ] || { [ -z "$HF_HUB_CACHE_SHARED" ] && share_question "$HF_HUB_CACHE_DIR"; }
}

check() {
  local dir
  dir="$(recorded HF_HUB_CACHE)"
  [ -n "$dir" ] && [ -d "$dir" ] && [ -w "$dir" ] &&
    { [ -z "$HF_HUB_CACHE_DIR" ] || [ "$dir" = "$HF_HUB_CACHE_DIR" ]; } &&
    [ -z "$(recorded HF_HOME)" ] && [ ! -L "$HF_HOME_DEFAULT" ] &&
    { [ "$HF_HUB_CACHE_SHARED" != yes ] || shared "$dir"; }
}

run() {
  local dir="$HF_HUB_CACHE_DIR" old legacy def answer share="$HF_HUB_CACHE_SHARED"
  case "$share" in "" | yes | no) ;; *) die "HF_HUB_CACHE_SHARED must be yes, no or empty, got '$share'" ;; esac
  old="$(recorded HF_HUB_CACHE)"
  legacy="$(legacy_home)"
  if [ -z "$dir" ]; then
    def="${HF_HUB_CACHE:-}"   # env.sh is loaded, so the recorded value wins over the system one
    if [ -z "$def" ] && [ -n "$legacy" ] && [ -d "$legacy/hub" ]; then def="$legacy/hub"; fi
    def="${def:-$HF_HOME_DEFAULT/hub}"
    read -r -p "HF_HUB_CACHE directory [$def]: " dir || true   # EOF: take the default
    dir="${dir:-$def}"
    dir="${dir/#\~/$HOME}"
    [ "$dir" != / ] && dir="${dir%/}"
  fi
  case "$dir" in /*) ;; *) die "HF_HUB_CACHE must be an absolute path: $dir" ;; esac
  [ -n "$legacy" ] && restore_home "$legacy"
  if share_question "$dir" && [ -z "$share" ]; then
    # Enter shares; no answer at all (EOF) never does.
    if read -r -p "Share $dir with every user of this server? [Y/n]: " answer; then
      case "$answer" in [nN]*) share=no ;; *) share=yes ;; esac
    else
      share=no
    fi
  fi
  if [ "$share" = yes ] && ! shared "$dir"; then
    bash "$MIP_ROOT/admin/share-hf-cache.sh" "$dir"
  fi
  if ! mkdir -p "$dir" || [ ! -w "$dir" ]; then
    die "cannot create or write to $dir; if someone else made it, ask them or root to run: admin/share-hf-cache.sh $dir"
  fi
  old="${old:-$HF_HOME_DEFAULT/hub}"
  if [ -d "$old" ] && [ -n "$(ls -A "$old")" ] && ! [ "$old" -ef "$dir" ]; then
    warn "downloads in $old were not moved to $dir; delete them when no longer needed"
  fi
  add_env HF_HUB_CACHE "${dir/#$HOME/\$HOME}"
  info "HF_HUB_CACHE = $dir"
}

note() {
  # The runner inherits the shell that started it, so a stale HF_HOME shows here.
  if [ -n "${HF_HOME:-}" ]; then echo "HF_HOME is still set in this shell: run 'unset HF_HOME' or open a new terminal"; fi
}

# shared DIR — every user may add and replace entries in DIR.
shared() { bash "$MIP_ROOT/admin/share-hf-cache.sh" --check "$1"; }

# share_question DIR — whether to ask about sharing DIR: it lies outside your
# home and is not shared already.
share_question() {
  [[ "$(realpath -m "$1")/" != "$(realpath -m "$HOME")/"* ]] && ! shared "$1"
}

# recorded VAR — the value env.sh exports for VAR (with $HOME expanded), or nothing.
recorded() {
  local v
  v="$(sed -n "s/^export $1=\"\(.*\)\"\$/\1/p" "$MIP_ENV_FILE" 2>/dev/null | tail -n 1)"
  printf '%s\n' "${v/#\$HOME/$HOME}"
}

# legacy_home — the relocated HF_HOME the former hf-home Step left (its export,
# else the target of the ~/.cache/huggingface symlink), or nothing.
legacy_home() {
  local d
  d="$(recorded HF_HOME)"
  if [ -z "$d" ] && [ -L "$HF_HOME_DEFAULT" ]; then d="$(readlink -f "$HF_HOME_DEFAULT")"; fi
  if [ -n "$d" ] || [ -L "$HF_HOME_DEFAULT" ]; then printf '%s\n' "${d:-$HF_HOME_DEFAULT}"; fi
}

# restore_home DIR — make ~/.cache/huggingface a real, private directory again,
# moving in the entries of DIR you own (token, stored_tokens, xet/, …) except
# hub/, and drop the HF_HOME export.
restore_home() {
  local src="$1" e
  if [ -L "$HF_HOME_DEFAULT" ]; then rm "$HF_HOME_DEFAULT"; fi
  mkdir -p "$HF_HOME_DEFAULT"
  chmod 700 "$HF_HOME_DEFAULT"
  if [ -d "$src" ] && ! [ "$src" -ef "$HF_HOME_DEFAULT" ]; then
    shopt -s nullglob dotglob
    for e in "$src"/*; do
      if [ "${e##*/}" = hub ]; then continue; fi
      if [ -e "$HF_HOME_DEFAULT/${e##*/}" ] || [ ! -O "$e" ]; then warn "left $e where it is"; continue; fi
      mv "$e" "$HF_HOME_DEFAULT/"
      info "moved $e to $HF_HOME_DEFAULT"
    done
  fi
  remove_env HF_HOME
}
