# The Pipeline's side of the Hugging Face cache folder, sourced by the hf-cache
# and hf-export Actions only. What a cache folder is (its layout, valid paths,
# shared, exported) is admin/share-hf-cache.sh's to say (docs/adr/0003): these
# helpers ask it. What stays here is what only the Pipeline can see: which
# folder this user's settings and env.sh point to.

# hf_admin ARG... — admin/share-hf-cache.sh, as you.
hf_admin() { bash "$MIP_ROOT/admin/share-hf-cache.sh" "$@"; }

# hf_cache_state DIR — fill HF_STATE with the script's --state for DIR (keys:
# folder hub datasets home owner shared writable exported). Exits 1, with the
# script's message, when DIR cannot be a cache folder. Call it directly, not
# in $(...): it sets a global.
declare -A HF_STATE=()
hf_cache_state() {
  local out k v
  HF_STATE=()
  out="$(hf_admin --state "$1")" || exit 1
  while IFS='=' read -r k v; do HF_STATE[$k]="$v"; done <<<"$out"
}

# hf_cache_mine_and_private — the folder HF_STATE describes holds only your
# own downloads: nobody else owns it and it is not shared in any way.
hf_cache_mine_and_private() { [ "${HF_STATE[owner]}" != other ] && [ "${HF_STATE[shared]}" = none ]; }

# hf_cache_folder PATH — PATH as a cache folder (~ expanded, no trailing /);
# fails, with the script's message, when it cannot be one.
hf_cache_folder() {
  local out
  out="$(hf_admin --state "$1")" || return 1
  sed -n 's/^folder=//p' <<<"$out"
}

# hf_cache_recorded — the cache folder env.sh records (the hf-cache Step's), or nothing.
hf_cache_recorded() {
  local hub
  hub="$(env_value HF_HUB_CACHE)"
  if [ -n "$hub" ]; then hf_admin --folder-of "$hub" "$(env_value HF_DATASETS_CACHE)"; fi
}

# hf_cache_resolve — the cache folder already decided, first found of: the
# HF_CACHE_DIR setting, the one env.sh records (the hf-cache Step's), the one
# exported for every user (read fresh, so root's export from earlier in this
# Run counts), the folder holding an HF_HUB_CACHE=<folder>/hub this shell has
# (an older export). Nothing when none is; fails when the setting cannot be a
# cache folder.
hf_cache_resolve() {
  local f
  if [ -n "${HF_CACHE_DIR:-}" ]; then hf_cache_folder "$HF_CACHE_DIR"; return; fi
  f="$(hf_cache_recorded)"
  [ -n "$f" ] || f="$(hf_admin --exported-folder)"
  if [ -z "$f" ] && [ -n "${HF_HUB_CACHE:-}" ]; then f="$(hf_admin --folder-of "$HF_HUB_CACHE")"; fi
  if [ -n "$f" ]; then printf '%s\n' "$f"; fi
}

# hf_ask_folder QUESTION DEFAULT — ask on the terminal for a cache folder; Enter,
# or no answer at all (EOF), takes DEFAULT. Prints it as hf_cache_folder does.
hf_ask_folder() {
  local f
  read -r -p "$1 [$2]: " f || true
  hf_cache_folder "${f:-$2}"
}
