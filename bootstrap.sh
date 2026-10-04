#!/usr/bin/env bash
# One-button entry point for a fresh server:
#
#   curl -fsSL https://raw.githubusercontent.com/scott306lr/my-init-pipeline/main/bootstrap.sh | bash
#   curl -fsSL .../bootstrap.sh | bash -s -- --dry-run      # any `init.sh run` options
#
# Clones (or fast-forwards) the repo to ~/my-init-pipeline, then runs the Pipeline.
# Under `curl | bash` stdin is the pipe, so the Run is handed the terminal via
# /dev/tty; with no terminal at all it runs non-interactively.
set -euo pipefail

# Everything lives in main, called on the last line: a truncated download
# defines a function that is never called instead of running half a script.
main() {
  local url="${MIP_REPO_URL:-https://github.com/scott306lr/my-init-pipeline.git}"
  local dir="${MIP_DIR:-$HOME/my-init-pipeline}"

  command -v git >/dev/null || { echo "error: git is required" >&2; exit 1; }
  command -v curl >/dev/null || { echo "error: curl is required" >&2; exit 1; }

  if [ -d "$dir/.git" ]; then
    git -C "$dir" pull --ff-only --quiet || echo "warning: could not update $dir; using it as is" >&2
  else
    git clone --quiet "$url" "$dir"
  fi

  if (: </dev/tty) 2>/dev/null; then
    exec "$dir/init.sh" run "$@" </dev/tty
  else
    exec "$dir/init.sh" run --non-interactive "$@"
  fi
}

main "$@"
