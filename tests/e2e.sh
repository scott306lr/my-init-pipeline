#!/usr/bin/env bash
# End-to-end: run the real Pipeline twice in a throwaway HOME with a clean PATH.
# The second Run must change nothing. Downloads real Tools (needs network).
#
#   tests/e2e.sh                # non-interactive; gh-auth deferred unless GH_TOKEN is set
#   GH_TOKEN=$(gh auth token) tests/e2e.sh   # also exercises claude-config and herdr
#   E2E_HOME=/path tests/e2e.sh # keep the HOME for inspection (or use a real one)
#   tests/e2e.sh -j 1           # extra args go to `init.sh run`
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
home="${E2E_HOME:-$(mktemp -d)}"
mkdir -p "$home"
echo "e2e HOME: $home"

# Settings that pass through the clean environment: config.sh overrides, the
# gh token, and git's SSH command (set it to something failing to test HTTPS-only).
passthrough=()
while IFS='=' read -r name _; do
  case "$name" in CLAUDE_SETUP_* | GH_TOKEN | GIT_SSH_COMMAND) passthrough+=("$name=${!name}") ;; esac
done < <(env)

pipeline() {
  env -i HOME="$home" USER="${USER:-}" TERM="${TERM:-dumb}" LANG=C.UTF-8 \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    "${passthrough[@]}" \
    "$root/init.sh" run --non-interactive "$@" </dev/null
}

echo "── first run"
pipeline "$@" || { echo "FAIL: first run failed"; exit 1; }

echo "── second run (must be a no-op)"
out="$(pipeline "$@")" || { echo "$out"; echo "FAIL: second run failed"; exit 1; }
echo "$out"
grep -q '^Run: 0 ran,' <<<"$out" || { echo "FAIL: second run changed something"; exit 1; }
echo "e2e OK"
