# The Action descriptor: what the runner knows about a Step's Action, read one
# way. Sourced by init.sh alongside lib/pipeline.sh, whose action_file it calls.
#
# An Action states static facts in its header comment (summary, check,
# interactive: yes, optional: yes, notes), which is read without running the
# Action, and its behaviour in functions (check, run, and optionally upgrade,
# note, interactive), which are only ever reached through lib/step.sh: a fresh
# shell with the managed env and config.sh loaded. Whether a function exists is
# asked (action_defines), never inferred from an exit status.

# action_header STEP — the leading comment block of the Step's Action file.
action_header() {
  awk 'NR==1 && /^#!/ {next} /^#/ {sub(/^# ?/, ""); print; next} {exit}' "$(action_file "$1")"
}

# action_field STEP FIELD — value of "# FIELD: value" in the header, if any.
action_field() {
  action_header "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -n 1
}

# step_call STEP FUNCTION [ARG...] — run one function of the Step's Action.
# Its status is the function's, 127 when the Action does not define it, or 126
# when the Action file cannot be loaded.
step_call() { bash "$MIP_ROOT/lib/step.sh" "$(action_file "$1")" "${@:2}"; }

# action_defines STEP FUNCTION — status 0 if the Step's Action defines
# FUNCTION, 1 if it does not, 126 if the Action file cannot be loaded.
action_defines() { step_call "$1" --defines "$2" >/dev/null 2>&1; }

# is_optional STEP — true if the header says `optional: yes`: offered, never run
# unless chosen.
is_optional() { [ "$(action_field "$1" optional)" = yes ]; }

# is_interactive STEP — true if the Step needs a human now: its header says
# `interactive: yes` and its interactive() function, if it defines one, agrees.
# An Action defines interactive() when a setting can answer its prompt, so a
# Run without a terminal still runs it once that setting is given.
is_interactive() {
  [ "$(action_field "$1" interactive)" = yes ] || return 1
  local rc=0
  action_defines "$1" interactive || rc=$?
  case "$rc" in
    0) step_call "$1" interactive >/dev/null 2>&1 ;;
    1) return 0 ;;
    *) return 1 ;;   # it cannot be loaded: no human can help; it fails where its log says why
  esac
}

# check_word STATUS — what a check() status means: done (0), na (2: it does not
# apply here), todo (anything else).
check_word() { case "$1" in 0) echo "done" ;; 2) echo na ;; *) echo todo ;; esac; }

# check_status STEP — the Step's Check now: done | na | todo, its output
# dropped (Checks must have no side effects).
check_status() {
  local rc=0
  step_call "$1" check >/dev/null 2>&1 || rc=$?
  check_word "$rc"
}
