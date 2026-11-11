#!/usr/bin/env bash
# Usage: step.sh ACTION_FILE FUNCTION [ARG...]
#        step.sh ACTION_FILE --defines FUNCTION
#
# Runs one function (check | run | upgrade | note | interactive) of an Action in a fresh
# shell, so Actions never see the runner's internals and every Step picks up
# PATH entries recorded by the Steps before it. This is the only place an
# Action is loaded.
#
# Exit codes: the function's own status, or 127 (the shell's "command not
# found") if the Action doesn't define it. With --defines: 0 if it does, else 1.
set -eo pipefail

MIP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
. "$MIP_ROOT/lib/common.sh"
load_env
# shellcheck source=config.sh
. "${MIP_USER_CONFIG:-$MIP_ROOT/config.sh}"
# shellcheck disable=SC1090
. "$1"

if [ "$2" = --defines ]; then
  if declare -F "${3:-}" >/dev/null; then exit 0; else exit 1; fi
fi
if ! declare -F "$2" >/dev/null; then
  echo "step.sh: $1 defines no $2()" >&2
  exit 127
fi
"$2" "${@:3}"
