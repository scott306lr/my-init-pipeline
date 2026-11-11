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

# shellcheck source=lib/hf-cache.sh
. "$MIP_ROOT/lib/hf-cache.sh"

HF_HOME_DEFAULT="$HOME/.cache/huggingface"
# The two caches in a cache folder, and the variable each is exported as.
declare -A CACHE_VAR=([hub]=HF_HUB_CACHE [datasets]=HF_DATASETS_CACHE)

interactive() {
  [ -n "$HF_CACHE_DIR" ] || return 0
  [ -z "$HF_CACHE_SHARED" ] || return 1
  hf_cache_state "$HF_CACHE_DIR"
  should_ask_to_share
}

check() {
  local root want
  root="$(hf_cache_recorded)"
  [ -n "$root" ] || return 1
  if [ -n "$HF_CACHE_DIR" ]; then
    want="$(hf_cache_folder "$HF_CACHE_DIR")" || return 1
    [ "$root" = "$want" ] || return 1
  fi
  hf_cache_state "$root"
  [ "${HF_STATE[writable]}" = yes ] &&
    [ -z "$(env_value HF_HOME)" ] && [ ! -L "$HF_HOME_DEFAULT" ] &&
    { [ "$HF_CACHE_SHARED" != yes ] || [ "${HF_STATE[shared]}" != none ]; }
}

run() {
  local root legacy answer share="$HF_CACHE_SHARED" kind
  local -A from=() to=()
  case "$share" in "" | yes | no) ;; *) die "HF_CACHE_SHARED must be yes, no or empty, got '$share'" ;; esac
  # Where the downloads are now, before anything changes.
  legacy="$(legacy_home)"
  for kind in "${!CACHE_VAR[@]}"; do
    from[$kind]="$(env_value "${CACHE_VAR[$kind]}")"
    if [ -z "${from[$kind]}" ] && [ -n "$legacy" ]; then from[$kind]="$legacy/$kind"; fi
    from[$kind]="${from[$kind]:-$HF_HOME_DEFAULT/$kind}"
  done
  root="$(hf_cache_resolve)" || return 1
  if [ -z "$HF_CACHE_DIR" ]; then
    if [ -z "$root" ] && [ -n "$legacy" ] && ! [ "$legacy" -ef "$HF_HOME_DEFAULT" ]; then root="$legacy"; fi
    root="$(hf_ask_folder "Hugging Face cache folder (holds hub/ and datasets/)" "${root:-$(suggestion)}")" || return 1
  fi
  if [ -n "$legacy" ]; then restore_home "$legacy"; fi
  hf_cache_state "$root"
  if should_ask_to_share && [ -z "$share" ]; then
    # Enter shares; no answer at all (EOF) never does.
    if read -r -p "Share $root with every user of this server? [Y/n]: " answer; then
      case "$answer" in [nN]*) share=no ;; *) share=yes ;; esac
    else
      share=no
    fi
  fi
  for kind in "${!CACHE_VAR[@]}"; do to[$kind]="${HF_STATE[$kind]}"; done
  if [ "${HF_STATE[shared]}" != none ]; then share=yes; fi   # a shared folder stays shared
  if mkdir -p "${to[@]}"; then hf_cache_state "$root"; fi
  if [ "${HF_STATE[writable]}" != yes ]; then
    die "cannot create or write to $root/hub and $root/datasets: $root needs root first; tick hf-export too (or run: ./init.sh run hf-export hf-cache), or ask an admin to run: admin/share-hf-cache.sh $root"
  fi
  move_then_share "$root" "$share"
  for kind in "${!CACHE_VAR[@]}"; do add_env "${CACHE_VAR[$kind]}" "${to[$kind]/#$HOME/\$HOME}"; done
  info "HF_HUB_CACHE = ${to[hub]}, HF_DATASETS_CACHE = ${to[datasets]}"
}

note() {
  local root
  root="$(hf_cache_recorded)"
  # The runner inherits the shell that started it, so a stale HF_HOME shows here.
  if [ -n "${HF_HOME:-}" ]; then echo "HF_HOME is still set in this shell: run 'unset HF_HOME' or open a new terminal"; fi
  # Exporting it for users who never run this Pipeline is the optional hf-export Step.
  [ -n "$root" ] || return 0
  hf_cache_state "$root"
  if [ "${HF_STATE[shared]}" != none ] && [ "${HF_STATE[exported]}" != yes ]; then
    echo "$root is shared; to make it every user's default (needs sudo): ./init.sh run hf-export"
  fi
}

# should_ask_to_share — the folder HF_STATE describes lies outside your home,
# is yours (or will be, once created) and is not shared in any way yet. A
# shared folder, or someone else's, is used as its owner set it up.
should_ask_to_share() { [ "${HF_STATE[home]}" = no ] && hf_cache_mine_and_private; }

# move_then_share ROOT SHARE — move your downloads from the caller's from[kind]
# into its to[kind], then share ROOT when SHARE is yes. The one order that
# works: sharing covers the entries you own in ROOT at that moment, so it has
# to come after whatever is moved in.
move_then_share() {
  local kind src
  for kind in "${!CACHE_VAR[@]}"; do
    src="${from[$kind]}"
    if [ -d "$src" ] && [ -n "$(ls -A "$src")" ] && ! [ "$src" -ef "${to[$kind]}" ]; then
      move_downloads "$src" "${to[$kind]}"
    fi
  done
  if [ "$2" = yes ]; then hf_admin "$1"; fi
}

# move_downloads SRC DST — move what SRC holds into DST, if SRC is a private
# cache of yours. A shared one (an ACL, or a setgid group), or one you don't
# own, holds other users' downloads: then it is only reported.
move_downloads() {
  local src="$1" dst="$2" left
  hf_cache_state "$src"
  if ! hf_cache_mine_and_private; then
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
