# summary: Put Hugging Face downloads (hub/) and the datasets cache (datasets/) in one cache folder: HF_CACHE_DIR from config.sh, else asked on the terminal
# check:   env.sh exports HF_HUB_CACHE=<folder>/hub and HF_DATASETS_CACHE=<folder>/datasets (the folder equal to HF_CACHE_DIR when set), both writable (and shared, when HF_CACHE_SHARED=yes); HF_HOME is not exported and ~/.cache/huggingface is a real directory
# interactive: yes
# notes:   The cache folder is laid out like HF_HOME (hub/ for models and
#          datasets downloaded from the Hub, datasets/ for the datasets
#          library's Arrow cache) but never holds the login token: HF_HOME
#          stays at ~/.cache/huggingface. The Run asks for the folder unless
#          HF_CACHE_DIR is set, defaulting to the one already in effect
#          (recorded here, else exported for every user, including by hf-export
#          earlier in this Run, else an older HF_HUB_CACHE=<folder>/hub), else
#          HF_CACHE_SUGGESTED if you can create it, else ~/.cache/huggingface.
#          For a folder outside your home that you own (or will create) and
#          that is not shared yet, it also asks whether to share it with every
#          user, unless HF_CACHE_SHARED (yes/no) answers; sharing runs
#          admin/share-hf-cache.sh as you, no sudo. A folder already shared is
#          used as it is shared (an ACL, or a setgid group). With both answered
#          the Step runs without a terminal.
#          It requires hf-export only to run after it: an Optional Step not
#          chosen counts as satisfied, but a chosen hf-export that fails or is
#          deferred leaves this Step blocked, because the folder may need what
#          root was to prepare.
#          Re-pointing moves your downloads: what the previous hub/ and
#          datasets/ caches hold (the recorded ones, else
#          ~/.cache/huggingface's) is merged into the new folder, keeping the
#          new folder's copy where both have an entry, then shared the way the
#          folder is. Downloads move only out of a private cache of yours.
#          Moving across disks copies, which takes a while for big models;
#          don't re-point while a download runs. An HF_HOME export or
#          ~/.cache/huggingface symlink left by the former hf-home Step is
#          undone: the entries you own at its target, except hub/ and
#          datasets/, move back into a real ~/.cache/huggingface, and that
#          target becomes the prompt's default.

HF_HOME_DEFAULT="$HOME/.cache/huggingface"
# The two caches in a cache folder, and the variable each is exported as.
declare -A CACHE_VAR=([hub]=HF_HUB_CACHE [datasets]=HF_DATASETS_CACHE)

interactive() {
  [ -z "$HF_CACHE_DIR" ] || { [ -z "$HF_CACHE_SHARED" ] && should_ask_to_share "$HF_CACHE_DIR"; }
}

check() {
  local root
  root="$(hf_cache_recorded)"
  [ -n "$root" ] && writable_caches "$root" &&
    { [ -z "$HF_CACHE_DIR" ] || [ "$root" = "$HF_CACHE_DIR" ]; } &&
    [ -z "$(env_value HF_HOME)" ] && [ ! -L "$HF_HOME_DEFAULT" ] &&
    { [ "$HF_CACHE_SHARED" != yes ] || share_hf_cache --check "$root"; }
}

run() {
  local root="$HF_CACHE_DIR" legacy def answer share="$HF_CACHE_SHARED" kind src
  local -A from=()
  case "$share" in "" | yes | no) ;; *) die "HF_CACHE_SHARED must be yes, no or empty, got '$share'" ;; esac
  # Where the downloads are now, before anything changes.
  legacy="$(legacy_home)"
  for kind in "${!CACHE_VAR[@]}"; do
    from[$kind]="$(env_value "${CACHE_VAR[$kind]}")"
    if [ -z "${from[$kind]}" ] && [ -n "$legacy" ]; then from[$kind]="$legacy/$kind"; fi
    from[$kind]="${from[$kind]:-$HF_HOME_DEFAULT/$kind}"
  done
  if [ -n "$root" ]; then
    root="$(folder_path "$root")"
  else
    def="$(hf_cache_in_effect)"
    if [ -z "$def" ] && [ -n "$legacy" ] && ! [ "$legacy" -ef "$HF_HOME_DEFAULT" ]; then def="$legacy"; fi
    root="$(ask_folder "Hugging Face cache folder (holds hub/ and datasets/)" "${def:-$(suggestion)}")"
  fi
  [ -n "$legacy" ] && restore_home "$legacy"
  if should_ask_to_share "$root" && [ -z "$share" ]; then
    # Enter shares; no answer at all (EOF) never does.
    if read -r -p "Share $root with every user of this server? [Y/n]: " answer; then
      case "$answer" in [nN]*) share=no ;; *) share=yes ;; esac
    else
      share=no
    fi
  fi
  local -a caches=()
  for kind in "${!CACHE_VAR[@]}"; do caches+=("$root/$kind"); done
  if ! mkdir -p "${caches[@]}" || ! writable_caches "$root"; then
    die "cannot create or write to $root/hub and $root/datasets: $root needs root first; tick hf-export too (or run: ./init.sh run hf-export hf-cache), or ask an admin to run: admin/share-hf-cache.sh $root"
  fi
  for kind in "${!CACHE_VAR[@]}"; do
    src="${from[$kind]}"
    if [ -d "$src" ] && [ -n "$(ls -A "$src")" ] && ! [ "$src" -ef "$root/$kind" ]; then
      move_downloads "$src" "$root/$kind"
    fi
  done
  # Sharing last, so it also covers whatever was just moved in.
  if [ "$share" = yes ] || share_hf_cache --check "$root"; then share_hf_cache "$root"; fi
  for kind in "${!CACHE_VAR[@]}"; do add_env "${CACHE_VAR[$kind]}" "${root/#$HOME/\$HOME}/$kind"; done
  info "HF_HUB_CACHE = $root/hub, HF_DATASETS_CACHE = $root/datasets"
}

note() {
  local root
  root="$(hf_cache_recorded)"
  # The runner inherits the shell that started it, so a stale HF_HOME shows here.
  if [ -n "${HF_HOME:-}" ]; then echo "HF_HOME is still set in this shell: run 'unset HF_HOME' or open a new terminal"; fi
  # Exporting it for users who never run this Pipeline is the optional hf-export Step.
  if [ -n "$root" ] && share_hf_cache --check "$root" && ! share_hf_cache --exported "$root"; then
    echo "$root is shared; to make it every user's default (needs sudo): ./init.sh run hf-export"
  fi
}

# move_downloads SRC DST — move what SRC holds into DST, if SRC is a private
# cache of yours. A shared one (an ACL, or a setgid group), or one you don't
# own, holds other users' downloads: then it is only reported.
move_downloads() {
  local src="$1" dst="$2" left
  if [ ! -O "$src" ] || share_hf_cache --check "$src"; then
    info "$src is shared with other users, so its downloads stay there"
    return
  fi
  info "moving $src into $dst ($(du -sh "$src" 2>/dev/null | cut -f1); across disks this copies)"
  shopt -s nullglob dotglob
  move_into "$src" "$dst"
  find "$src" -depth -type d -empty -delete 2>/dev/null || true
  if [ -e "$src" ]; then
    left="$(find "$src" ! -type d | wc -l)"
    warn "$left entries were already in $dst and stay behind in $src; delete them when no longer needed"
  fi
}

# move_into SRC DST — merge SRC's entries into DST. A directory on both sides is
# merged; any other entry already in DST is kept there and left in SRC. Hub
# blobs are named by their content hash and snapshot links are relative, so
# merged caches stay valid. Caller sets nullglob and dotglob.
move_into() {
  local src="$1" dst="$2" e name
  for e in "$src"/*; do
    name="${e##*/}"
    if [ ! -e "$dst/$name" ] && [ ! -L "$dst/$name" ]; then
      mv "$e" "$dst/"
    elif [ -d "$e" ] && [ ! -L "$e" ] && [ -d "$dst/$name" ] && [ ! -L "$dst/$name" ]; then
      move_into "$e" "$dst/$name"
    fi
  done
}

# should_ask_to_share DIR — DIR lies outside your home, is yours (or will be,
# once created) and is not shared in any way yet. A shared folder, or someone
# else's, is used as its owner set it up.
should_ask_to_share() {
  ! in_home "$1" && { [ ! -e "$1" ] || [ -O "$1" ]; } && ! share_hf_cache --check "$1"
}

# suggestion — the folder to offer when none is in effect: HF_CACHE_SUGGESTED
# if you can create or write it, else HF's default (your downloads move along).
suggestion() {
  local p="${HF_CACHE_SUGGESTED:-}"
  if [ -n "$p" ]; then
    while [ ! -e "$p" ]; do p="${p%/*}"; p="${p:-/}"; done   # nearest existing ancestor
    if [ -d "$p" ] && [ -w "$p" ]; then echo "$HF_CACHE_SUGGESTED"; return; fi
  fi
  echo "$HF_HOME_DEFAULT"
}

# writable_caches ROOT — you can write to both caches in ROOT.
writable_caches() {
  local kind
  for kind in "${!CACHE_VAR[@]}"; do [ -w "$1/$kind" ] || return 1; done
}

# legacy_home — the relocated HF_HOME the former hf-home Step left (its export,
# else the target of the ~/.cache/huggingface symlink), or nothing.
legacy_home() {
  local d
  d="$(env_value HF_HOME)"
  if [ -z "$d" ] && [ -L "$HF_HOME_DEFAULT" ]; then d="$(readlink -f "$HF_HOME_DEFAULT")"; fi
  if [ -n "$d" ] || [ -L "$HF_HOME_DEFAULT" ]; then printf '%s\n' "${d:-$HF_HOME_DEFAULT}"; fi
}

# restore_home DIR — make ~/.cache/huggingface a real, private directory again,
# moving in the entries of DIR you own (token, stored_tokens, xet/, …) except
# the caches (hub/, datasets/), and drop the HF_HOME export.
restore_home() {
  local src="$1" e
  if [ -L "$HF_HOME_DEFAULT" ]; then rm "$HF_HOME_DEFAULT"; fi
  mkdir -p "$HF_HOME_DEFAULT"
  chmod 700 "$HF_HOME_DEFAULT"
  if [ -d "$src" ] && ! [ "$src" -ef "$HF_HOME_DEFAULT" ]; then
    shopt -s nullglob dotglob
    for e in "$src"/*; do
      case "${e##*/}" in hub | datasets) continue ;; esac
      if [ -e "$HF_HOME_DEFAULT/${e##*/}" ] || [ ! -O "$e" ]; then warn "left $e where it is"; continue; fi
      mv "$e" "$HF_HOME_DEFAULT/"
      info "moved $e to $HF_HOME_DEFAULT"
    done
  fi
  remove_env HF_HOME
}
