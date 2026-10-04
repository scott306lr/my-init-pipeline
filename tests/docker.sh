#!/usr/bin/env bash
# Clean-room run in ubuntu:22.04 as a non-root user with no SSH key, so every
# GitHub clone goes over HTTPS.
#
#   tests/docker.sh                    # non-interactive Run, twice; second must be a no-op
#   tests/docker.sh --interactive      # shell in the container; run ./init.sh run yourself
#                                      # (no GH_TOKEN passed, so gh-auth really prompts)
#   CLAUDE_SETUP_REF=my-branch tests/docker.sh   # test a setup-repo branch before merging
#
# GH_TOKEN comes from the environment or `gh auth token`. It is passed by name
# (docker run -e GH_TOKEN), so it never appears on a command line.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image=my-init-pipeline-test

docker build -t "$image" -f "$root/tests/docker/Dockerfile" "$root"

run_args=(--rm -e CLAUDE_SETUP_PROTOCOL=https -e CLAUDE_SETUP_REF="${CLAUDE_SETUP_REF:-}")

if [ "${1:-}" = --interactive ]; then
  exec docker run -it "${run_args[@]}" -w /home/tester/my-init-pipeline "$image" bash -l
fi

GH_TOKEN="${GH_TOKEN:-$(gh auth token 2>/dev/null || true)}"
[ -n "$GH_TOKEN" ] || echo "warning: no GH_TOKEN; gh-auth is deferred, so claude-config and herdr are skipped" >&2
export GH_TOKEN
docker run "${run_args[@]}" -e GH_TOKEN "$image" \
  bash -c 'E2E_HOME="$HOME" ~/my-init-pipeline/tests/e2e.sh'
