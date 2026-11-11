# Helpers shared by the runner and by every Action. Sourced, never executed.
#
# Paths honour XDG overrides so tests can redirect everything by changing HOME.

MIP_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/my-init-pipeline"
# shellcheck disable=SC2034 # used by Actions and init.sh
MIP_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/my-init-pipeline"
MIP_ENV_FILE="$MIP_CONFIG_DIR/env.sh"
MIP_BASHRC="${MIP_BASHRC:-$HOME/.bashrc}"
MIP_MARK_BEGIN="# >>> my-init-pipeline >>>"
MIP_MARK_END="# <<< my-init-pipeline <<<"

info() { printf '  %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# root_outside_container — true when running as root on a real machine. As in
# Homebrew's installer (check_run_command_as_root), root is normal in a container
# or a CI job, so those count as not. bootstrap.sh keeps its own copy (it runs
# before the clone exists).
root_outside_container() {
  [ "$EUID" = 0 ] || return 1
  if [ -f /.dockerenv ] || [ -f /run/.containerenv ]; then return 1; fi
  if [ -f /proc/1/cgroup ] && grep -Eq 'azpl_job|actions_job|docker|garden|kubepods' /proc/1/cgroup; then return 1; fi
}

# in_home DIR — true if DIR is your home directory or lies below it.
in_home() { [[ "$(realpath -m "$1")/" == "$(realpath -m "$HOME")/"* ]]; }

# hub_parent HUB — the folder holding HUB when HUB is <folder>/hub, else nothing.
hub_parent() { case "$1" in */hub) printf '%s\n' "${1%/hub}" ;; esac; }

# hf_cache_root HUB DATASETS — the cache folder holding both, when HUB is
# <folder>/hub and DATASETS is <folder>/datasets; else nothing.
hf_cache_root() {
  local f
  f="$(hub_parent "$1")"
  if [ -n "$f" ] && [ "$2" = "$f/datasets" ]; then printf '%s\n' "$f"; fi
}

# hf_cache_recorded — the cache folder env.sh records (the hf-cache Step's), or nothing.
hf_cache_recorded() { hf_cache_root "$(env_value HF_HUB_CACHE)" "$(env_value HF_DATASETS_CACHE)"; }

# hf_cache_in_effect — the Hugging Face cache folder already chosen, first found
# of: the one env.sh records (the hf-cache Step's), the one exported for every
# user (read fresh, so root's export from earlier in this Run counts), the
# folder holding an HF_HUB_CACHE=<folder>/hub this shell has (an older export).
# Nothing when none is.
hf_cache_in_effect() {
  local f
  f="$(hf_cache_recorded)"
  [ -n "$f" ] || f="$(share_hf_cache --exported-folder)"
  [ -n "$f" ] || f="$(hub_parent "${HF_HUB_CACHE:-}")"
  if [ -n "$f" ]; then printf '%s\n' "$f"; fi
}

# folder_path PATH — PATH as a cache folder: ~ expanded, no trailing /, and
# absolute; dies on anything else (including / itself).
folder_path() {
  local f="${1/#\~/$HOME}"
  f="${f%/}"
  case "$f" in /?*) printf '%s\n' "$f" ;; *) die "the cache folder must be an absolute path other than /: ${1:-<empty>}" ;; esac
}

# ask_folder QUESTION DEFAULT — ask on the terminal for a cache folder; Enter,
# or no answer at all (EOF), takes DEFAULT. Prints it as folder_path does.
ask_folder() {
  local f
  read -r -p "$1 [$2]: " f || true
  folder_path "${f:-$2}"
}

# share_hf_cache [--check | --exported] DIR | --exported-folder —
# admin/share-hf-cache.sh: share DIR with every user (as its owner), ask whether
# it is shared / exported, or print the folder exported for every user.
share_hf_cache() { bash "$MIP_ROOT/admin/share-hf-cache.sh" "$@"; }

# have CMD — true if CMD resolves on PATH.
have() { command -v "$1" >/dev/null 2>&1; }

# load_env — pull the managed env file into the current shell, so PATH entries
# added by earlier Steps are visible to later ones.
load_env() {
  # shellcheck disable=SC1090
  [ -f "$MIP_ENV_FILE" ] && . "$MIP_ENV_FILE"
  return 0
}

# env_file_init — create the managed env file (with its header) if missing.
env_file_init() {
  mkdir -p "$MIP_CONFIG_DIR"
  [ -f "$MIP_ENV_FILE" ] || printf '# Managed by my-init-pipeline (lib/common.sh add_path / add_shell_init / add_env).\n' >"$MIP_ENV_FILE"
}

# add_path DIR — persist DIR at the front of PATH via the managed env file.
# Pass DIR unexpanded (e.g. '$HOME/.local/bin') so the file stays portable.
add_path() {
  local dir="$1" line
  # The guard keeps PATH free of duplicates however often env.sh is sourced.
  line="case \":\$PATH:\" in *\":$dir:\"*) ;; *) export PATH=\"$dir:\$PATH\" ;; esac"
  env_file_init
  grep -qxF "$line" "$MIP_ENV_FILE" || printf '%s\n' "$line" >>"$MIP_ENV_FILE"
  load_env
}

# add_shell_init LINE — persist LINE in the managed env file, run only by
# interactive shells (prompt hooks, `eval "$(tool init bash)"`, aliases).
add_shell_init() {
  local line="case \$- in *i*) $1 ;; esac"
  env_file_init
  grep -qxF "$line" "$MIP_ENV_FILE" || printf '%s\n' "$line" >>"$MIP_ENV_FILE"
}

# env_has_shell_init LINE — true if add_shell_init LINE has already been recorded.
env_has_shell_init() {
  [ -f "$MIP_ENV_FILE" ] && grep -qxF "case \$- in *i*) $1 ;; esac" "$MIP_ENV_FILE"
}

# add_env VAR VALUE — persist `export VAR="VALUE"` in the managed env file for
# every shell, replacing an earlier value of VAR. Pass VALUE unexpanded
# ('$HOME/x') so the file stays portable.
add_env() {
  local var="$1" line="export $1=\"$2\""
  env_file_init
  grep -qxF "$line" "$MIP_ENV_FILE" && return 0
  remove_env "$var"
  printf '%s\n' "$line" >>"$MIP_ENV_FILE"
  load_env
}

# remove_env VAR — drop VAR's export from the managed env file, if any.
remove_env() {
  if [ -f "$MIP_ENV_FILE" ]; then sed -i "/^export $1=/d" "$MIP_ENV_FILE"; fi
}

# env_value VAR — the value env.sh exports for VAR (with $HOME expanded), or nothing.
env_value() {
  local v
  v="$(sed -n "s/^export $1=\"\(.*\)\"\$/\1/p" "$MIP_ENV_FILE" 2>/dev/null | tail -n 1)"
  printf '%s\n' "${v/#\$HOME/$HOME}"
}

# env_has_env VAR VALUE — true if add_env VAR VALUE is the recorded value.
env_has_env() {
  [ -f "$MIP_ENV_FILE" ] && grep -qxF "export $1=\"$2\"" "$MIP_ENV_FILE"
}

# env_has_path DIR — true if add_path DIR has already been recorded.
env_has_path() {
  [ -f "$MIP_ENV_FILE" ] && grep -qF "*\":$1:\"*)" "$MIP_ENV_FILE"
}

# hook_bashrc — append the single marker block that sources env.sh (idempotent).
hook_bashrc() {
  bashrc_hooked && return 0
  {
    printf '\n%s\n' "$MIP_MARK_BEGIN"
    printf '[ -f "%s" ] && . "%s"\n' "${MIP_ENV_FILE/#$HOME/\$HOME}" "${MIP_ENV_FILE/#$HOME/\$HOME}"
    printf '%s\n' "$MIP_MARK_END"
  } >>"$MIP_BASHRC"
}

bashrc_hooked() { [ -f "$MIP_BASHRC" ] && grep -qxF "$MIP_MARK_BEGIN" "$MIP_BASHRC"; }

# fetch URL DEST — download with retries; fails on HTTP errors.
fetch() { curl -fsSL --retry 3 --retry-delay 2 -o "$2" "$1"; }

# run_installer URL [ENV=VAL...] — download an install script, then run it with sh.
# Downloading first (rather than piping) makes a truncated download fail loudly.
run_installer() {
  local url="$1" tmp
  shift
  tmp="$(mktemp)"
  fetch "$url" "$tmp" || { rm -f "$tmp"; return 1; }
  env "$@" sh "$tmp" </dev/null
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

# github_latest_tag OWNER/REPO — latest release tag, resolved from the
# /releases/latest redirect (no API call, so no unauthenticated rate limit).
github_latest_tag() {
  local url
  url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest")" || return 1
  printf '%s\n' "${url##*/}"
}

# machine_arch — x86_64 or aarch64 (dies on anything else); Actions map it to
# each project's own asset naming.
machine_arch() {
  case "$(uname -m)" in
    x86_64 | amd64) echo x86_64 ;;
    aarch64 | arm64) echo aarch64 ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac
}

# release_sha256 CHECKSUMS_URL FILE — FILE's hash from a "<sha256>  <file>" list.
release_sha256() {
  curl -fsSL --retry 3 "$1" | awk -v f="$2" '$2 == f || $2 == "*" f { print $1; exit }'
}

# install_release_binary URL BIN [SHA256] [DIR] — download a .tar.gz release
# asset, verify it when a hash is given, and install the executable named BIN
# (found anywhere in the archive) as DIR/BIN (default ~/.local/bin/BIN).
install_release_binary() {
  local url="$1" bin="$2" sha="${3:-}" dir="${4:-$HOME/.local/bin}" tmp path rc=0
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/x" "$dir"
  {
    fetch "$url" "$tmp/asset.tar.gz" &&
      if [ -n "$sha" ]; then echo "$sha  $tmp/asset.tar.gz" | sha256sum -c -; else info "no published checksum for ${url##*/}"; fi &&
      tar -xzf "$tmp/asset.tar.gz" -C "$tmp/x" &&
      path="$(find "$tmp/x" -type f -name "$bin" -perm -u+x | head -n 1)" &&
      [ -n "$path" ] &&
      install -m 755 "$path" "$dir/$bin"
  } || rc=1
  rm -rf "$tmp"
  [ "$rc" = 0 ] || { warn "could not install $bin from $url"; return 1; }
  info "installed $bin from ${url##*/}"
}
