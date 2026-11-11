#!/usr/bin/env bash
# my-init-pipeline — bring a fresh server to the declared state, without root.
#
#   ./init.sh run [STEP...] [options]   run the Pipeline (or STEPs + what they require);
#                                       on a terminal with no STEP, pick Steps first
#   ./init.sh update [COMMAND...]       pull the latest my-init-pipeline (fast-forward
#                                       only), then run COMMAND with it, e.g. `update run --upgrade`
#   ./init.sh list                      Step → Action → requires → check → summary
#   ./init.sh describe STEP             full description of one Step
#   ./init.sh help
#
# run options:
#   --force STEP        run STEP even if its Check passes (repeatable)
#   --upgrade           for every Step whose Check passes, call its upgrade() (Tools'
#                       updaters, a pull of the claude setup repo); no checklist
#   -j, --jobs N        parallel Steps (default: number of CPUs; 1 = serial)
#   --non-interactive   skip Interactive Steps (and what requires them)
#   --dry-run           print the plan with current Check results; change nothing
#   -y, --yes           no checklist: run every Step that is not done (but
#                       optional ones, which run only when named or ticked)
#
# Environment overrides (mainly for tests): MIP_CONF, MIP_ACTIONS_DIR, MIP_USER_CONFIG,
# MIP_HEARTBEAT (seconds of silence before a "still running" line; default 30),
# MIP_GUM (the checklist's gum), MIP_UV_INSTALLER_URL (the uv Step's installer),
# MIP_HF_PROFILE and MIP_HF_ENVIRONMENT (the system-wide HF cache export's two
# files, which admin/share-hf-cache.sh reads and, as root, writes).
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
# shellcheck source=lib/checklist.sh
. "$MIP_ROOT/lib/checklist.sh"

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
  local dry=0 yes=0 rc=0 picked mode=install
  local -A FORCE=() UPGRADE=()
  declare -gA STEP_MODE=() UNCHOSEN=()
  MIP_JOBS="$(nproc 2>/dev/null || echo 4)"
  MIP_INTERACTIVE=1
  while [ $# -gt 0 ]; do
    case "$1" in
      --force) [ $# -ge 2 ] || die "--force needs a step"; FORCE[$2]=1; shift ;;
      --upgrade) mode=upgrade ;;
      -j | --jobs) [[ "${2:-}" =~ ^[1-9][0-9]*$ ]] || die "$1 needs a positive number"; MIP_JOBS="$2"; shift ;;
      --non-interactive) MIP_INTERACTIVE=0 ;;
      --dry-run) dry=1 ;;
      -y | --yes) yes=1 ;;
      -*) die "unknown option $1 (see: ./init.sh help)" ;;
      *) targets+=("$1") ;;
    esac
    shift
  done

  if [ "$dry" = 0 ]; then refuse_root; fi
  load_pipeline
  local s
  for s in "${targets[@]}" "${!FORCE[@]}"; do need_step "$s"; done

  # Like create-t3-app: ask on a terminal, unless told what to do (Steps named,
  # -y, an upgrade or a dry run, which must not download the checklist's gum).
  if [ ${#targets[@]} -eq 0 ] && [ ${#FORCE[@]} -eq 0 ] && [ "$yes" = 0 ] && [ "$dry" = 0 ] &&
    [ "$mode" = install ] && [ "$MIP_INTERACTIVE" = 1 ] && [ -t 0 ] && [ -t 1 ]; then
    picked="$(checklist)" || rc=$?
    if [ "$rc" = 130 ]; then echo "Cancelled; nothing was run."; return 130; fi
    if [ "$rc" != 0 ]; then
      warn "could not show the checklist (gum v$GUM_VERSION unavailable); running every Step"
    elif [ -z "$picked" ]; then
      echo "No Steps selected; nothing to do."; return 0
    else
      mapfile -t targets <<<"$picked"
      # Ticked although done: upgrade it, or re-run it if it has no upgrade().
      for s in "${targets[@]}"; do
        [ "$(check_status "$s")" = "done" ] || continue
        if action_defines "$s" upgrade; then UPGRADE[$s]=1; else FORCE[$s]=1; fi
      done
    fi
  fi

  local -a plan
  mapfile -t plan < <(pipeline_select "${targets[@]}")
  local -A chosen=()
  for s in "${targets[@]}" "${!FORCE[@]}"; do chosen[$s]=1; done
  for s in "${plan[@]}"; do
    if [ -n "${FORCE[$s]:-}" ]; then STEP_MODE[$s]=force
    elif [ -n "${UPGRADE[$s]:-}" ]; then STEP_MODE[$s]=upgrade
    else STEP_MODE[$s]="$mode"; fi
    if is_optional "$s" && [ -z "${chosen[$s]:-}" ]; then UNCHOSEN[$s]=1; fi
  done

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
  local env_before
  env_before="$(env_digest)"
  rc=0
  pipeline_run "${plan[@]}" || rc=$?
  shell_hint "$env_before"
  return "$rc"
}

# refuse_root — everything lands in the invoking user's home, so sudo would set
# up root's account and leave root-owned files in yours; the one Step that needs
# root, hf-export, asks for sudo itself. Containers and CI jobs run as root
# legitimately, as Homebrew's installer allows.
refuse_root() {
  if root_outside_container; then
    die "don't run my-init-pipeline as root (sudo): run it as yourself; a Step that needs root asks for sudo itself"
  fi
}

env_digest() { cksum "$MIP_ENV_FILE" 2>/dev/null || true; }

# shell_hint DIGEST_BEFORE — a child process can't update the calling shell, so
# say how to pick up the change when env.sh now adds PATH entries the caller
# lacks, or when this Run changed env.sh at all (e.g. a new shell hook).
shell_hint() {
  [ -f "$MIP_ENV_FILE" ] || return 0
  local updated
  # shellcheck disable=SC1090
  updated="$(PATH="$MIP_CALLER_PATH" bash -c '. "$1" && printf %s "$PATH"' _ "$MIP_ENV_FILE")" || return 0
  if [ "$updated" = "$MIP_CALLER_PATH" ] && [ "$(env_digest)" = "$1" ]; then return 0; fi
  printf '\nShell setup changed. To use it in this shell, run:  source %s\n' "${MIP_BASHRC/#$HOME/\~}"
}

# cmd_update [COMMAND...] — fast-forward this checkout to its upstream (like
# `brew update`), then hand COMMAND to the new init.sh. Bash reads a script as
# it runs, so nothing of this one runs after the pull but the exec.
cmd_update() {
  refuse_root   # a pull as root leaves root-owned files in your checkout
  git -C "$MIP_ROOT" rev-parse --git-dir >/dev/null 2>&1 || die "$MIP_ROOT is not a git checkout; re-run bootstrap.sh"
  git -C "$MIP_ROOT" pull --ff-only --quiet ||
    die "could not fast-forward $MIP_ROOT (local commits or conflicting changes); sort it out with git, then retry"
  echo "my-init-pipeline: $(git -C "$MIP_ROOT" log -1 --format='%h %s')"
  if [ $# -gt 0 ]; then exec "$MIP_ROOT/init.sh" "$@"; fi
}

case "${1:-help}" in
  run) shift; cmd_run "$@" ;;
  update) shift; cmd_update "$@" ;;
  list) shift; cmd_list "$@" ;;
  describe) shift; cmd_describe "$@" ;;
  help | -h | --help) usage ;;
  *) usage >&2; exit 2 ;;
esac
