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

# have CMD — true if CMD resolves on PATH.
have() { command -v "$1" >/dev/null 2>&1; }

# load_env — pull the managed env file into the current shell, so PATH entries
# added by earlier Steps are visible to later ones.
load_env() {
  # shellcheck disable=SC1090
  [ -f "$MIP_ENV_FILE" ] && . "$MIP_ENV_FILE"
  return 0
}

# add_path DIR — persist DIR at the front of PATH via the managed env file.
# Pass DIR unexpanded (e.g. '$HOME/.local/bin') so the file stays portable.
add_path() {
  local dir="$1" line
  # The guard keeps PATH free of duplicates however often env.sh is sourced.
  line="case \":\$PATH:\" in *\":$dir:\"*) ;; *) export PATH=\"$dir:\$PATH\" ;; esac"
  mkdir -p "$MIP_CONFIG_DIR"
  [ -f "$MIP_ENV_FILE" ] || printf '# Managed by my-init-pipeline (lib/common.sh add_path / add_shell_init).\n' >"$MIP_ENV_FILE"
  grep -qxF "$line" "$MIP_ENV_FILE" || printf '%s\n' "$line" >>"$MIP_ENV_FILE"
  load_env
}

# add_shell_init LINE — persist LINE in the managed env file, run only by
# interactive shells (prompt hooks, `eval "$(tool init bash)"`, aliases).
add_shell_init() {
  local line="case \$- in *i*) $1 ;; esac"
  mkdir -p "$MIP_CONFIG_DIR"
  [ -f "$MIP_ENV_FILE" ] || printf '# Managed by my-init-pipeline (lib/common.sh add_path / add_shell_init).\n' >"$MIP_ENV_FILE"
  grep -qxF "$line" "$MIP_ENV_FILE" || printf '%s\n' "$line" >>"$MIP_ENV_FILE"
}

# env_has_shell_init LINE — true if add_shell_init LINE has already been recorded.
env_has_shell_init() {
  [ -f "$MIP_ENV_FILE" ] && grep -qxF "case \$- in *i*) $1 ;; esac" "$MIP_ENV_FILE"
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
