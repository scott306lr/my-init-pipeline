#!/usr/bin/env bash
# my-init-pipeline — bring a fresh server to the declared state, without root.
#
#   ./init.sh run [STEP...] [options]   run the Pipeline (or STEPs + what they require)
#   ./init.sh list                      Step → Action → requires → check → summary
#   ./init.sh describe STEP             full description of one Step
#   ./init.sh help
#
# run options:
#   --force STEP        run STEP even if its Check passes (repeatable)
#   --upgrade           for Steps whose Check passes, call the Tool's updater
#   -j, --jobs N        parallel Steps (default: number of CPUs; 1 = serial)
#   --non-interactive   skip Interactive Steps (and what requires them)
#   --dry-run           print the plan with current Check results; change nothing
#
# Environment overrides (mainly for tests): MIP_CONF, MIP_ACTIONS_DIR, MIP_USER_CONFIG,
# MIP_HEARTBEAT (seconds of silence before a "still running" line; default 30).
set -uo pipefail

MIP_CALLER_PATH="$PATH"   # the invoking shell's PATH, before anything here changes it
MIP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIP_CONF="${MIP_CONF:-$MIP_ROOT/pipeline.conf}"
MIP_ACTIONS_DIR="${MIP_ACTIONS_DIR:-$MIP_ROOT/actions}"
export MIP_ROOT MIP_CONF MIP_ACTIONS_DIR

# shellcheck source=lib/common.sh
. "$MIP_ROOT/lib/common.sh"
# shellcheck source=lib/pipeline.sh
. "$MIP_ROOT/lib/pipeline.sh"

usage() { sed -n '2,/^set /{/^set /d;s/^# \{0,1\}//;p}' "$0"; }

load_pipeline() {
  pipeline_load "$MIP_CONF" || exit 2
  pipeline_validate || exit 2
}

need_step() { [[ -v ACTION[$1] ]] || die "unknown step '$1' (see: ./init.sh list)"; }

cmd_list() {
  load_pipeline
  local s
  printf '%-15s %-16s %-24s %-6s %s\n' STEP ACTION REQUIRES CHECK SUMMARY
  for s in "${STEPS[@]}"; do
    printf '%-15s %-16s %-24s %-6s %s\n' "$s" "${ACTION[$s]}" "${REQ[$s]:--}" \
      "$(check_status "$s")" "$(action_field "$s" summary)"
  done
}

cmd_describe() {
  [ $# -eq 1 ] || die "usage: ./init.sh describe STEP"
  load_pipeline
  need_step "$1"
  printf 'step:        %s\n' "$1"
  printf 'action:      %s (%s)\n' "${ACTION[$1]}" "$(action_file "$1")"
  printf 'requires:    %s\n' "${REQ[$1]:--}"
  printf 'required by: %s\n' "$(required_by "$1" | sed 's/^$/-/')"
  printf 'check now:   %s\n\n' "$(check_status "$1")"
  action_header "$1"
}

cmd_run() {
  local -a targets=()
  local dry=0
  declare -gA FORCE=()
  MIP_JOBS="$(nproc 2>/dev/null || echo 4)"
  MIP_MODE=install
  MIP_INTERACTIVE=1
  while [ $# -gt 0 ]; do
    case "$1" in
      --force) [ $# -ge 2 ] || die "--force needs a step"; FORCE[$2]=1; shift ;;
      --upgrade) MIP_MODE=upgrade ;;
      -j | --jobs) [[ "${2:-}" =~ ^[1-9][0-9]*$ ]] || die "$1 needs a positive number"; MIP_JOBS="$2"; shift ;;
      --non-interactive) MIP_INTERACTIVE=0 ;;
      --dry-run) dry=1 ;;
      -*) die "unknown option $1 (see: ./init.sh help)" ;;
      *) targets+=("$1") ;;
    esac
    shift
  done
  export MIP_MODE

  load_pipeline
  local s
  for s in "${targets[@]}" "${!FORCE[@]}"; do need_step "$s"; done

  local -a plan
  mapfile -t plan < <(pipeline_select "${targets[@]}")

  if [ "$dry" = 1 ]; then
    printf '%-15s %-6s %-12s %s\n' STEP CHECK INTERACTIVE REQUIRES
    for s in "${plan[@]}"; do
      printf '%-15s %-6s %-12s %s\n' "$s" "$(check_status "$s")" \
        "$(is_interactive "$s" && echo yes || echo no)" "${REQ[$s]:--}"
    done
    echo "(dry run: Check results are for the current state; nothing was changed)"
    return 0
  fi

  if [ "$MIP_INTERACTIVE" = 1 ] && ! { [ -t 0 ] && [ -t 1 ]; }; then
    echo "No terminal attached: running non-interactively (Interactive Steps are skipped)."
    MIP_INTERACTIVE=0
  fi

  RUN_DIR="$MIP_STATE_DIR/runs/$(date +%Y%m%d-%H%M%S)-$$"
  mkdir -p "$RUN_DIR" && ln -sfn "$RUN_DIR" "$MIP_STATE_DIR/runs/latest"
  printf 'Pipeline: %d step(s), up to %d in parallel%s\n\n' "${#plan[@]}" "$MIP_JOBS" \
    "$([ "$MIP_INTERACTIVE" = 0 ] && echo ', non-interactive')"
  local rc=0
  pipeline_run "${plan[@]}" || rc=$?
  path_hint
  return "$rc"
}

# path_hint — a child process can't update the calling shell, so if env.sh now
# adds PATH entries the caller's shell lacks, say how to pick them up.
path_hint() {
  [ -f "$MIP_ENV_FILE" ] || return 0
  local updated
  # shellcheck disable=SC1090
  updated="$(PATH="$MIP_CALLER_PATH" bash -c '. "$1" && printf %s "$PATH"' _ "$MIP_ENV_FILE")" || return 0
  [ "$updated" = "$MIP_CALLER_PATH" ] && return 0
  printf '\nPATH changed. To use the new tools in this shell, run:  source %s\n' "${MIP_BASHRC/#$HOME/\~}"
}

case "${1:-help}" in
  run) shift; cmd_run "$@" ;;
  list) shift; cmd_list "$@" ;;
  describe) shift; cmd_describe "$@" ;;
  help | -h | --help) usage ;;
  *) usage >&2; exit 2 ;;
esac
