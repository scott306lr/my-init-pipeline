# Shared fixtures: a throwaway HOME plus a fake Pipeline whose Actions record
# what they did in $T/events and mark themselves "installed" via $T/state/<name>.

bats_require_minimum_version 1.12.0   # run -N, bats::on_failure (tests/run.sh pins the version)

ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

# When a test fails, show the Step logs of the last Run it made, if it made one.
bats::on_failure() {
  local log
  for log in "$HOME/.local/state/my-init-pipeline/runs/latest"/*.log; do
    [ -f "$log" ] || continue
    echo "--- $log"
    cat "$log"
  done
}

setup_pipeline() {
  export T="$BATS_TEST_TMPDIR"
  export HOME="$T/home"
  export MIP_CONF="$T/pipeline.conf" MIP_ACTIONS_DIR="$T/actions" MIP_USER_CONFIG="$T/config.sh"
  unset XDG_CONFIG_HOME XDG_STATE_HOME
  export MIP_GUM="$T/no-gum"   # never download the checklist's gum; fake_gum replaces it
  export MIP_HF_PROFILE="$T/profile.d/hf-cache.sh"   # never this machine's /etc/profile.d
  export MIP_HF_ENVIRONMENT="$T/environment"         # nor its /etc/environment
  mkdir -p "$HOME" "$MIP_ACTIONS_DIR" "$T/state"
  : >"$MIP_USER_CONFIG"
  : >"$T/events"
  : >"$MIP_CONF"
}

# step NAME [REQUIRES...] — append a Step bound to an Action of the same name.
step() { echo "$*" | awk '{ $1 = $1 " " $1; print }' >>"$MIP_CONF"; }

# fake_action NAME [--interactive] [--answered-by VAR] [--optional] [--fail] [--na]
#                  [--sleep S] [--stays-unsatisfied] [--upgrade] [--note TEXT]
# --answered-by VAR: Interactive, but needs no human once VAR is set.
fake_action() {
  local name="$1" interactive="" answered_by="" optional="" fail=0 na=0 sleep=0 satisfy=1 upgrade=0 note=""
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --interactive) interactive="# interactive: yes" ;;
      --answered-by) interactive="# interactive: yes"; answered_by="$2"; shift ;;
      --optional) optional="# optional: yes" ;;
      --fail) fail=1 ;;
      --na) na=1 ;;
      --sleep) sleep="$2"; shift ;;
      --stays-unsatisfied) satisfy=0 ;;
      --upgrade) upgrade=1 ;;
      --note) note="$2"; shift ;;
    esac
    shift
  done
  {
    echo "# summary: fake $name"
    echo "# check:   state file exists"
    [ -n "$interactive" ] && echo "$interactive"
    [ -n "$optional" ] && echo "$optional"
    echo
    if [ "$na" = 1 ]; then
      echo "check() { return 2; }"
    else
      echo "check() { [ -f \"\$T/state/$name\" ]; }"
    fi
    echo "run() {"
    echo "  echo \"start $name tty=\$([ -t 0 ] && echo y || echo n)\" >>\"\$T/events\""
    echo "  sleep $sleep"
    [ "$fail" = 1 ] && echo "  echo 'boom from $name'; return 1"
    [ "$satisfy" = 1 ] && echo "  touch \"\$T/state/$name\""
    echo "  echo \"end $name\" >>\"\$T/events\""
    echo "}"
    [ "$upgrade" = 1 ] && echo "upgrade() { echo \"upgrade $name\" >>\"\$T/events\"; }"
    if [ -n "$answered_by" ]; then echo "interactive() { [ -z \"\${$answered_by:-}\" ]; }"; fi
    if [ -n "$note" ]; then echo "note() { echo '$note'; }"; fi
  } >"$MIP_ACTIONS_DIR/$name.sh"
}

# action NAME FUNCTION [ARG...] — one function of the real Action NAME, the way
# the runner calls it. Settings go in front: HF_CACHE_DIR=/x run action hf-cache check
action() { bash "$ROOT/lib/step.sh" "$ROOT/actions/$1.sh" "${@:2}"; }

# fake_tool NAME [BODY] — a Tool NAME on PATH that runs BODY (bash), or what
# stdin holds when BODY is not given. BODY sees $T.
fake_tool() {
  mkdir -p "$T/bin"
  {
    echo '#!/usr/bin/env bash'
    if [ $# -ge 2 ]; then printf '%s\n' "$2"; else cat; fi
  } >"$T/bin/$1"
  chmod +x "$T/bin/$1"
  case ":$PATH:" in *":$T/bin:"*) ;; *) export PATH="$T/bin:$PATH" ;; esac
}

mip() { "$ROOT/init.sh" "$@"; }

# mip_tty ARGS... — init.sh run on a pseudo-terminal (util-linux script).
mip_tty() { script -qec "$ROOT/init.sh $*" /dev/null; }

# fake_gum [STATUS] [STEP...] — a gum whose `choose` records its arguments in
# $T/gum.args and "ticks" the given Steps, or exits STATUS (e.g. 130, cancel).
fake_gum() {
  local status="${1:-0}"
  shift || true
  {
    echo '#!/usr/bin/env bash'
    echo 'printf "%s\n" "$@" >"$T/gum.args"'
    [ "$status" != 0 ] && echo "exit $status"
    for s in "$@"; do echo "echo $s"; done
  } >"$T/gum"
  chmod +x "$T/gum"
  export MIP_GUM="$T/gum"
}

events() { cat "$T/events"; }

# line_of PATTERN — line number of the first event matching PATTERN.
line_of() { grep -n -m1 -- "$1" "$T/events" | cut -d: -f1; }

# hf_state DIR KEY — one value of admin/share-hf-cache.sh --state DIR.
hf_state() { bash "$ROOT/admin/share-hf-cache.sh" --state "$1" | sed -n "s/^$2=//p"; }

# export_for_everyone DIR — what root's run of the script leaves, in the test's
# stand-ins for /etc/profile.d and /etc/environment.
export_for_everyone() {
  mkdir -p "$(dirname "$MIP_HF_PROFILE")"
  printf 'export HF_HUB_CACHE=%s/hub\nexport HF_DATASETS_CACHE=%s/datasets' "$1" "$1" >"$MIP_HF_PROFILE"
  printf 'HF_HUB_CACHE=%s/hub\nHF_DATASETS_CACHE=%s/datasets\n' "$1" "$1" >>"$MIP_HF_ENVIRONMENT"
}
