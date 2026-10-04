# Shared fixtures: a throwaway HOME plus a fake Pipeline whose Actions record
# what they did in $T/events and mark themselves "installed" via $T/state/<name>.

ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup_pipeline() {
  export T="$BATS_TEST_TMPDIR"
  export HOME="$T/home"
  export MIP_CONF="$T/pipeline.conf" MIP_ACTIONS_DIR="$T/actions" MIP_USER_CONFIG="$T/config.sh"
  unset XDG_CONFIG_HOME XDG_STATE_HOME
  mkdir -p "$HOME" "$MIP_ACTIONS_DIR" "$T/state"
  : >"$MIP_USER_CONFIG"
  : >"$T/events"
  : >"$MIP_CONF"
}

# step NAME [REQUIRES...] — append a Step bound to an Action of the same name.
step() { echo "$*" | awk '{ $1 = $1 " " $1; print }' >>"$MIP_CONF"; }

# fake_action NAME [--interactive] [--fail] [--na] [--sleep S] [--stays-unsatisfied]
#                  [--upgrade] [--note TEXT]
fake_action() {
  local name="$1" interactive="" fail=0 na=0 sleep=0 satisfy=1 upgrade=0 note=""
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --interactive) interactive="# interactive: yes" ;;
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
    if [ -n "$note" ]; then echo "note() { echo '$note'; }"; fi
  } >"$MIP_ACTIONS_DIR/$name.sh"
}

mip() { "$ROOT/init.sh" "$@"; }

events() { cat "$T/events"; }

# line_of PATTERN — line number of the first event matching PATTERN.
line_of() { grep -n -m1 -- "$1" "$T/events" | cut -d: -f1; }
