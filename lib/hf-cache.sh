# The Pipeline's side of the Hugging Face Cache folder, sourced by the hf-cache
# and hf-export Actions only. What a Cache folder is (its layout, valid paths,
# Shared, Exported) is admin/share-hf-cache.sh's to say (docs/adr/0003): these
# helpers ask it. What stays here is what only the Pipeline can see: which
# folder this user's settings and env.sh point to.

# The script that owns the Cache folder's rules. hf-export also runs it, under sudo.
HF_ADMIN_SCRIPT="$MIP_ROOT/admin/share-hf-cache.sh"

# hf_admin ARG... — that script, as you.
hf_admin() { bash "$HF_ADMIN_SCRIPT" "$@"; }

# hf_cache_state DIR — fill HF_STATE with the script's --state for DIR: folder,
# home, owner, shared, writable, exported, one key per cache variable, and
# vars, their names (see hf_cache_vars). Status 1, with the script's message, when DIR cannot be a
# Cache folder. It sets a variable, so call it directly, not in $(...); a
# caller that must keep the HF_STATE it has declares `local -A HF_STATE` first.
declare -A HF_STATE=()
hf_cache_state() {
  local out k v
  HF_STATE=()
  out="$(hf_admin --state "$1")" || return 1
  while IFS='=' read -r k v; do
    HF_STATE[$k]="$v"
    case "$k" in *[!A-Z_]*) ;; *) HF_STATE[vars]+="${HF_STATE[vars]:+ }$k" ;; esac
  done <<<"$out"
}

# hf_cache_vars — the variables that point into the folder HF_STATE describes
# (HF_HUB_CACHE, HF_DATASETS_CACHE), one per line, in the script's order;
# HF_STATE[variable] is the cache each points to. They are --state's keys in
# capitals, as the script's header says.
hf_cache_vars() {
  local var
  for var in ${HF_STATE[vars]:-}; do printf '%s\n' "$var"; done
}

# hf_cache_mine_and_private — the directory HF_STATE describes holds only your
# own downloads: nobody else owns it and it is not Shared in any way.
hf_cache_mine_and_private() { [ "${HF_STATE[owner]}" != other ] && [ "${HF_STATE[shared]}" = none ]; }

# hf_cache_folder PATH — PATH as a Cache folder (~ expanded, no trailing /);
# status 1, with the script's message, when it cannot be one.
hf_cache_folder() {
  local -A HF_STATE=()
  hf_cache_state "$1" || return 1
  printf '%s\n' "${HF_STATE[folder]}"
}

# hf_cache_recorded — the Cache folder env.sh records (the hf-cache Step's), or nothing.
hf_cache_recorded() { hf_admin --folder-in "$MIP_ENV_FILE"; }

# hf_cache_layout — how a Cache folder is laid out, for a prompt: "hub/ and
# datasets/". Read off the state of a folder that need not exist.
hf_cache_layout() {
  local -A HF_STATE=()
  local var layout=""
  hf_cache_state /any/cache-folder || return 0
  for var in $(hf_cache_vars); do layout+="${layout:+ and }${HF_STATE[$var]##*/}/"; done
  printf '%s\n' "$layout"
}

# hf_cache_resolve — the Cache folder already decided, first found of: the
# HF_CACHE_DIR setting, the one env.sh records (the hf-cache Step's), the one
# login shells get (read fresh, so root's export from earlier in this Run
# counts), the folder this shell's first cache variable points into (an older
# export set only HF_HUB_CACHE). Nothing when none is; status 1 when the
# setting cannot be a Cache folder.
hf_cache_resolve() {
  local f
  if [ -n "${HF_CACHE_DIR:-}" ]; then hf_cache_folder "$HF_CACHE_DIR"; return; fi
  f="$(hf_cache_recorded)"
  [ -n "$f" ] || f="$(hf_admin --exported-folder)"
  [ -n "$f" ] || f="$(hf_admin --folder-in-env)"
  if [ -n "$f" ]; then printf '%s\n' "$f"; fi
}

# hf_ask_folder QUESTION DEFAULT — ask on the terminal for a Cache folder; Enter,
# or no answer at all (EOF), takes DEFAULT. Prints it as hf_cache_folder does.
hf_ask_folder() {
  local f
  read -r -p "$1 [$2]: " f || true
  hf_cache_folder "${f:-$2}"
}
