# Shared fixtures: a throwaway HOME plus a fake Pipeline whose Actions record
# what they did in $T/events and mark themselves "installed" via $T/state/<name>.

ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup_pipeline() {
  export T="$BATS_TEST_TMPDIR"
  export HOME="$T/home"
  export MIP_CONF="$T/pipeline.conf" MIP_ACTIONS_DIR="$T/actions" MIP_USER_CONFIG="$T/config.sh"
  unset XDG_CONFIG_HOME XDG_STATE_HOME
  export MIP_GUM="$T/no-gum"   # never download the checklist's gum; fake_gum replaces it
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
