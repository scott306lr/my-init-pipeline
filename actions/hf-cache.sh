# summary: Export HF_HUB_CACHE (Hugging Face model and dataset downloads): HF_HUB_CACHE_DIR from config.sh, else asked on the terminal
# check:   env.sh exports HF_HUB_CACHE (equal to HF_HUB_CACHE_DIR when set) and you can write to it; HF_HOME is not exported and ~/.cache/huggingface is a real directory
# interactive: yes
# notes:   Only the hub cache is relocated. HF_HOME stays at its default,
#          ~/.cache/huggingface, so the login token (and other per-user state)
#          never lands on a shared or big disk. To share downloads between
#          users, point HF_HUB_CACHE_DIR at a directory set up once by root with
#          admin/share-hf-cache.sh. With HF_HUB_CACHE_DIR set nothing is asked,
#          so the Step also runs without a terminal; otherwise the Run prompts
#          once, defaulting to the HF_HUB_CACHE already in effect (recorded here,
#          or set system-wide by that script), and Enter keeps it. Re-pointing does not move existing downloads (they
#          are re-fetched on use; a shared cache must not hold files only one
#          user can write). An HF_HOME export or ~/.cache/huggingface symlink
#          left by the former hf-home Step is undone: the entries you own at its
#          target, except hub/, move back into a real ~/.cache/huggingface, and
#          that hub/ becomes the prompt's default.

HF_HOME_DEFAULT="$HOME/.cache/huggingface"

interactive() { [ -z "$HF_HUB_CACHE_DIR" ]; }

check() {
  local dir
  dir="$(recorded HF_HUB_CACHE)"
  [ -n "$dir" ] && [ -d "$dir" ] && [ -w "$dir" ] &&
    { [ -z "$HF_HUB_CACHE_DIR" ] || [ "$dir" = "$HF_HUB_CACHE_DIR" ]; } &&
    [ -z "$(recorded HF_HOME)" ] && [ ! -L "$HF_HOME_DEFAULT" ]
}

run() {
  local dir="$HF_HUB_CACHE_DIR" old legacy def
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
  if ! mkdir -p "$dir" || [ ! -w "$dir" ]; then die "cannot create or write to $dir (just added to its group? log in again, then re-run)"; fi
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
