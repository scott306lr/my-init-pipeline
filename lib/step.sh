#!/usr/bin/env bash
# Usage: step.sh ACTION_FILE FUNCTION
#
# Runs one function (check | run | upgrade | note) of an Action in a fresh
# shell, so Actions never see the runner's internals and every Step picks up
# PATH entries recorded by the Steps before it.
#
# Exit codes: the function's own status, or 3 if the Action doesn't define it.
set -eo pipefail

MIP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
. "$MIP_ROOT/lib/common.sh"
load_env
# shellcheck source=config.sh
. "${MIP_USER_CONFIG:-$MIP_ROOT/config.sh}"
# shellcheck disable=SC1090
. "$1"

declare -F "$2" >/dev/null || exit 3
"$2"
