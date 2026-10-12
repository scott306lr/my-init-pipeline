# summary: Export HF_HOME (Hugging Face cache, token, hub downloads): HF_HOME_DIR from config.sh, else asked on the terminal
# check:   env.sh exports HF_HOME, that directory exists (and equals HF_HOME_DIR when set), and ~/.cache/huggingface is it or links to it
# interactive: yes
# notes:   With HF_HOME_DIR set nothing is asked. Otherwise the Run prompts once;
#          the default is the HF_HOME already recorded, else ~/.cache/huggingface,
#          and Enter keeps it. To change it later: `./init.sh run --force hf-home hf-home`
#          asks again, or set HF_HOME_DIR. The new path must be absolute and
#          writable; it is created if missing. Whatever the previous locations
#          hold (the recorded HF_HOME and ~/.cache/huggingface) is moved into it,
#          merging directories; a file present in both is kept at the new path and
#          left behind at the old one, with a warning. A path nested inside an old
#          one (or the reverse) is refused. ~/.cache/huggingface then becomes a
#          symlink to the new path, so programs started without this shell's
#          environment (cron, an IDE from the desktop) find the same cache. The
#          export in ~/.config/my-init-pipeline/env.sh is replaced, never stacked.

HF_DEFAULT="$HOME/.cache/huggingface"

check() {
  local dir
  dir="$(recorded_dir)"
  [ -n "$dir" ] && [ -d "$dir" ] && { [ -z "$HF_HOME_DIR" ] || [ "$dir" = "$HF_HOME_DIR" ]; } && [ "$HF_DEFAULT" -ef "$dir" ]
}

run() {
  local dir="$HF_HOME_DIR" old src
  local -a sources=()
  old="$(recorded_dir)"
  if [ -z "$dir" ]; then
    read -r -p "HF_HOME directory [${old:-$HF_DEFAULT}]: " dir || true   # EOF: take the default
    dir="${dir:-${old:-$HF_DEFAULT}}"
    dir="${dir/#\~/$HOME}"
    [ "$dir" != / ] && dir="${dir%/}"
  fi
  case "$dir" in /*) ;; *) die "HF_HOME must be an absolute path: $dir" ;; esac
  # Back to the default while it is our symlink: it must become a real directory.
  if [ -L "$HF_DEFAULT" ] && [ "$dir" = "$HF_DEFAULT" ]; then rm "$HF_DEFAULT"; fi
  for src in "$old" "$HF_DEFAULT"; do
    if [ -z "$src" ] || ! has_content "$src" || [ "$src" -ef "$dir" ]; then continue; fi
    [ ${#sources[@]} -gt 0 ] && [ "$src" -ef "${sources[0]}" ] && continue
    nested "$dir" "$src" && die "$dir is inside the current HF_HOME $src; pick a path outside it"
    nested "$src" "$dir" && die "$dir contains the current HF_HOME $src; pick a path outside it"
    sources+=("$src")
  done
  if ! mkdir -p "$dir" || [ ! -w "$dir" ]; then die "cannot create or write to $dir"; fi
  shopt -s nullglob dotglob
  for src in "${sources[@]}"; do
    info "moving the contents of $src to $dir (a different disk takes a while)"
    move_into "$src" "$dir"
    if [ -L "$src" ]; then rm "$src"; else rmdir "$src" 2>/dev/null || warn "$src is not empty; see above"; fi
  done
  if ! [ "$HF_DEFAULT" -ef "$dir" ]; then
    if [ -d "$HF_DEFAULT" ] && [ ! -L "$HF_DEFAULT" ]; then rmdir "$HF_DEFAULT" 2>/dev/null || true; fi   # an empty leftover
    if [ -L "$HF_DEFAULT" ] || [ ! -e "$HF_DEFAULT" ]; then
      mkdir -p "${HF_DEFAULT%/*}"
      ln -sfn "$dir" "$HF_DEFAULT"
      info "$HF_DEFAULT -> $dir"
    else
      warn "$HF_DEFAULT still has files, so it was not replaced by a symlink to $dir"
    fi
  fi
  add_env HF_HOME "${dir/#$HOME/\$HOME}"
  info "HF_HOME = $dir"
}

# recorded_dir — the HF_HOME env.sh exports (with $HOME expanded), or nothing.
recorded_dir() {
  local v
  v="$(sed -n 's/^export HF_HOME="\(.*\)"$/\1/p' "$MIP_ENV_FILE" 2>/dev/null | tail -n 1)"
  printf '%s\n' "${v/#\$HOME/$HOME}"
}

# has_content DIR — true if DIR is a directory with at least one entry.
has_content() { [ -d "$1" ] && [ -n "$(ls -A "$1")" ]; }

# nested INNER OUTER — true if INNER is OUTER or lies somewhere below it.
nested() {
  local inner outer
  inner="$(realpath -m "$1")" outer="$(realpath -m "$2")"
  [ "$inner" = "$outer" ] || [[ "$inner/" == "$outer/"* ]]
}

# move_into SRC DST — move SRC's entries into DST, merging directories that exist
# on both sides. A file (or symlink) present in both stays as it is in DST and
# is left behind in SRC. Caller sets nullglob and dotglob.
move_into() {
  local src="$1" dst="$2" e name
  for e in "$src"/*; do
    name="${e##*/}"
    if [ ! -e "$dst/$name" ] && [ ! -L "$dst/$name" ]; then
      mv "$e" "$dst/"
    elif [ -d "$e" ] && [ ! -L "$e" ] && [ -d "$dst/$name" ] && [ ! -L "$dst/$name" ]; then
      move_into "$e" "$dst/$name"
      rmdir "$e" 2>/dev/null || true
    else
      warn "kept $dst/$name; $e left behind"
    fi
  done
}
