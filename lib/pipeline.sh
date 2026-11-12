# Pipeline model and scheduler. Sourced by init.sh; expects MIP_ROOT, MIP_CONF
# and MIP_ACTIONS_DIR to be set and lib/common.sh to be loaded. Its functions
# call lib/action.sh's, and lib/action.sh's call action_file here, so both
# files are sourced before either is used.

# Step results: word -> "MARK KIND". KIND says what the result means for the
# Run: ok (it worked), skip (nothing to do), fail (the Run fails), left (not
# completed). Dependents of an ok or skip Step may start.
declare -A RESULTS=(
  [ran]="✓ ok"          # Check failed, Action ran, Check passed afterwards
  [upgraded]="↑ ok"     # upgrade mode: Check passed and the Action's upgrade() ran
  [done]="= skip"       # Check already passed
  [na]="- skip"         # Check reported "not applicable here" (exit 2)
  [optional]="○ skip"   # an Optional Step with work to do, not chosen (like Debian's Suggests)
  [failed]="✗ fail"     # Action or post-run Check failed
  [deferred]="⏸ left"   # Interactive Step in a non-interactive Run
  [blocked]="⊘ left"    # a required Step failed, was deferred, or was blocked
  [aborted]="⊘ left"    # not started because another Step failed
)
result_kind() { local r="${RESULTS[$1]:-? left}"; printf '%s\n' "${r#* }"; }

declare -a STEPS=()        # Step names in pipeline.conf order
declare -A ACTION=()       # step -> action name
declare -A REQ=()          # step -> space-separated required step names
declare -a TOPO=()         # Step names in dependency order (conf order breaks ties)

# ── model ─────────────────────────────────────────────────────────────────────

pipeline_load() {
  local file="$1" lineno=0 line step
  local -a f
  STEPS=() ACTION=() REQ=()
  [ -f "$file" ] || { warn "no pipeline file at $file"; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    line="${line%%#*}"
    read -r -a f <<<"$line"
    [ ${#f[@]} -eq 0 ] && continue
    if [ ${#f[@]} -lt 2 ]; then
      warn "$file:$lineno: expected 'step action [requires...]'"
      return 1
    fi
    step="${f[0]}"
    if [[ -v ACTION[$step] ]]; then
      warn "$file:$lineno: step '$step' is defined twice"
      return 1
    fi
    ACTION[$step]="${f[1]}"
    REQ[$step]="${f[*]:2}"
    STEPS+=("$step")
  done <"$file"
}

action_file() { printf '%s/%s.sh\n' "$MIP_ACTIONS_DIR" "${ACTION[$1]}"; }

# pipeline_validate — names, action files, requires, cycles. Prints every problem.
pipeline_validate() {
  local s d bad=0
  for s in "${STEPS[@]}"; do
    [[ "$s" =~ ^[A-Za-z0-9._-]+$ ]] || { warn "step '$s': invalid name"; bad=1; }
    [ -f "$(action_file "$s")" ] || { warn "step '$s': no action file $(action_file "$s")"; bad=1; }
    for d in ${REQ[$s]}; do
      [ "$d" = "$s" ] && { warn "step '$s' requires itself"; bad=1; continue; }
      [[ -v ACTION[$d] ]] || { warn "step '$s' requires unknown step '$d'"; bad=1; }
    done
  done
  [ "$bad" = 0 ] || return 1
  pipeline_topo || { warn "dependency cycle among: $(pipeline_unsorted)"; return 1; }
}

# pipeline_topo — fill TOPO; always takes the earliest ready Step in conf order.
pipeline_topo() {
  local -A emitted=()
  local s d ok progress
  TOPO=()
  while [ ${#TOPO[@]} -lt ${#STEPS[@]} ]; do
    progress=0
    for s in "${STEPS[@]}"; do
      [[ -v emitted[$s] ]] && continue
      ok=1
      for d in ${REQ[$s]}; do [[ -v emitted[$d] ]] || { ok=0; break; }; done
      if [ "$ok" = 1 ]; then TOPO+=("$s"); emitted[$s]=1; progress=1; break; fi
    done
    [ "$progress" = 1 ] || return 1
  done
}

pipeline_unsorted() {
  local s out=()
  for s in "${STEPS[@]}"; do [[ " ${TOPO[*]} " == *" $s "* ]] || out+=("$s"); done
  printf '%s\n' "${out[*]}"
}

# pipeline_select STEP... — print, in TOPO order, the targets plus everything they
# transitively require. No arguments selects the whole Pipeline.
pipeline_select() {
  local -A want=()
  local -a queue=("$@")
  local s d
  if [ $# -eq 0 ]; then printf '%s\n' "${TOPO[@]}"; return; fi
  while [ ${#queue[@]} -gt 0 ]; do
    s="${queue[0]}"; queue=("${queue[@]:1}")
    [[ -v want[$s] ]] && continue
    want[$s]=1
    for d in ${REQ[$s]}; do queue+=("$d"); done
  done
  for s in "${TOPO[@]}"; do [[ -v want[$s] ]] && printf '%s\n' "$s"; done
}

# required_by STEP — Steps that list STEP in their requires.
required_by() {
  local s out=()
  for s in "${STEPS[@]}"; do [[ " ${REQ[$s]} " == *" $1 "* ]] && out+=("$s"); done
  printf '%s\n' "${out[*]}"
}

# ── the Plan ──────────────────────────────────────────────────────────────────

# What this Run was asked to do. init.sh fills FORCE and UPGRADE (from --force
# and the checklist's ticks); pipeline_choose derives the rest, which
# pipeline_run and the dry run read.
declare -A FORCE=()        # step -> 1: run it even if its Check passes
declare -A UPGRADE=()      # step -> 1: upgrade it if its Check passes
declare -a SELECTED=()     # the Steps this Run covers, in dependency order
declare -A STEP_MODE=()    # step -> install | upgrade | force: what to do when its Check passes
declare -A UNCHOSEN=()     # step -> 1: an Optional Step nobody chose: skipped while it has work to do

# pipeline_choose MODE [TARGET...] — select TARGETs and what they require (the
# whole Pipeline when none is named) into SELECTED, and settle each selected
# Step's mode and whether it is an Optional Step left unchosen. MODE (install |
# upgrade) is the mode of every Step in neither FORCE nor UPGRADE. Named and
# forced Steps count as chosen.
pipeline_choose() {
  local mode="$1" s
  local -A chosen=()
  shift
  STEP_MODE=() UNCHOSEN=()
  mapfile -t SELECTED < <(pipeline_select "$@")
  for s in "$@" "${!FORCE[@]}"; do chosen[$s]=1; done
  for s in "${SELECTED[@]}"; do
    if [ -n "${FORCE[$s]:-}" ]; then STEP_MODE[$s]=force
    elif [ -n "${UPGRADE[$s]:-}" ]; then STEP_MODE[$s]=upgrade
    else STEP_MODE[$s]="$mode"; fi
    if is_optional "$s" && [ -z "${chosen[$s]:-}" ]; then UNCHOSEN[$s]=1; fi
  done
}

# step_plan CHECK MODE UNCHOSEN INTERACTIVE TERMINAL HAS_UPGRADE — what a Run
# intends for one Step (GLOSSARY: Plan). Every rule about it is here, and
# nothing else: it reads no state and runs nothing.
#   CHECK        done | na | todo: the Step's Check now (ignored when MODE is force)
#   MODE         install | upgrade | force
#   UNCHOSEN     yes | no: an Optional Step that was not chosen
#   INTERACTIVE  yes | no: the Step needs a human
#   TERMINAL     yes | no: the Run has one
#   HAS_UPGRADE  yes | no: the Action defines upgrade()
# Prints one of:
#   na        the Check does not apply here
#   done      the Check passes and there is nothing to upgrade, or the upgrade
#             needs a human and there is no terminal (what requires it still runs)
#   upgrade   the Check passes: call upgrade()
#   optional  work to do, but an Optional Step nobody chose
#   deferred  work to do that needs a human, and no terminal
#   run       call run()
step_plan() {
  local check="$1" mode="$2" unchosen="$3" interactive="$4" terminal="$5" has_upgrade="$6" human=yes
  if [ "$interactive" = yes ] && [ "$terminal" != yes ]; then human=no; fi   # needed, and not there
  if [ "$mode" != force ]; then
    case "$check" in
      na) echo na; return ;;
      done)
        if [ "$mode" = upgrade ] && [ "$has_upgrade" = yes ] && [ "$human" = yes ]; then echo upgrade; else echo "done"; fi
        return ;;
    esac
  fi
  if [ "$unchosen" = yes ]; then echo optional
  elif [ "$human" = no ]; then echo deferred
  else echo run; fi
}

# step_decide STEP INTERACTIVE — take STEP's Check and print its Plan for this
# Run. It only gathers step_plan's inputs (the Check, this Run's choices, what
# the Action defines) and applies no rule itself, so it takes the Check and
# asks about upgrade() even where the Plan will not turn on them. INTERACTIVE
# is yes | no. The Check's output goes to fd 9.
step_decide() {
  local step="$1" rc=0 unchosen=no terminal=no has_upgrade=no
  echo "-- check" >&9
  step_call "$step" check >&9 2>&9 || rc=$?
  if [ -n "${UNCHOSEN[$step]:-}" ]; then unchosen=yes; fi
  if [ "${MIP_INTERACTIVE:-0}" = 1 ]; then terminal=yes; fi
  if action_defines "$step" upgrade; then has_upgrade=yes; fi
  step_plan "$(check_word "$rc")" "${STEP_MODE[$step]:-install}" "$unchosen" "$2" "$terminal" "$has_upgrade"
}

# ── execution ─────────────────────────────────────────────────────────────────

# The Plans that do work: plan -> "STARTED RESULT", the word announced while
# the Step works and its result word when the work succeeds. Each is also the
# name of the Action function that does the work.
declare -A WORK=([run]="installing ran" [upgrade]="upgrading upgraded")

# step_execute STEP INTERACTIVE — one Step of the Run: take its Check, plan,
# and do the work the Plan calls for, leaving the result word in
# RUN_DIR/STEP.result. INTERACTIVE (yes | no) says how the work is wired:
#   no   in the background: all output goes to the Step's log
#   yes  by the scheduler itself, owning the terminal: no redirection, so
#        prompts and tty detection work; only bookkeeping goes to the log
step_execute() {
  local step="$1" interactive="$2" log="$RUN_DIR/$1.log" plan result rc=0
  echo "== $step (action: ${ACTION[$step]}, ${STEP_MODE[$step]:-install}$([ "$interactive" = yes ] && echo ', interactive')) $(date '+%F %T')" >>"$log"
  plan="$(step_decide "$step" "$interactive" 9>>"$log")"
  if [[ -v WORK[$plan] ]]; then
    if [ "$interactive" = yes ]; then
      printf '▶ %s (interactive)\n' "$step"
      step_work "$step" "$plan" </dev/tty 9>>"$log" || rc=$?
    else
      echo "${WORK[$plan]% *}" >"$RUN_DIR/$step.started"
      step_work "$step" "$plan" >>"$log" 2>&1 9>>"$log" || rc=$?
    fi
    result=failed
    if [ "$rc" = 0 ]; then
      result="${WORK[$plan]#* }"
      step_note "$step" "$result"
    fi
  else
    result="${plan:-failed}"   # a Plan that does no work is the result; none at all is a failure
  fi
  echo "RESULT $result" >>"$log"
  printf '%s\n' "$result" >"$RUN_DIR/$step.result"
}

# step_work STEP PLAN — call the Action function a working Plan names; after
# run(), the Check decides success. The Action's own output goes to stdout and
# stderr; progress lines and that Check's output go to fd 9.
step_work() {
  local step="$1" plan="$2"
  echo "-- $plan" >&9
  step_call "$step" "$plan" || return 1
  if [ "$plan" = run ]; then
    echo "-- check (after run)" >&9
    if ! step_call "$step" check >&9 2>&9; then
      echo "check still fails after run" >&9
      return 1
    fi
  fi
}

# step_note STEP RESULT — leave the Note of a Step that worked, if its Action
# writes one; note() gets the result word. A note() that fails is logged, and
# does not fail the Step.
step_note() {
  action_defines "$1" note || return 0
  step_call "$1" note "$2" >"$RUN_DIR/$1.note" 2>>"$RUN_DIR/$1.log" || echo "note() failed" >>"$RUN_DIR/$1.log"
}

report() {
  local step="$1" result="$2" secs="${3:-}" mark extra=""
  mark="${RESULTS[$result]:-?}"; mark="${mark%% *}"
  case "$result" in   # what to do next, for the results that need something
    failed) extra="  log: $RUN_DIR/$step.log" ;;
    deferred) extra="  (interactive; rerun with a terminal)" ;;
    optional) extra="  (optional; to run it: ./init.sh run $step)" ;;
  esac
  [ -n "$secs" ] && secs="${secs}s"
  printf '%s %-16s %-9s %5s%s\n' "$mark" "$step" "$result" "$secs" "$extra"
}

is_satisfied() { case "$(result_kind "$1")" in ok | skip) return 0 ;; esac; return 1; }
is_dead() { case "$1" in failed | deferred | blocked | aborted) return 0 ;; esac; return 1; }

# pipeline_run — run the SELECTED Steps as pipeline_choose left them: start
# each once what it requires is satisfied, up to MIP_JOBS at a time, taking
# the terminal for Interactive ones when MIP_INTERACTIVE is 1. Logs and
# results go to a new RUN_DIR under the state directory. Returns 1 if any
# Step failed.
pipeline_run() {
  local -A state=() pid=() start=() announced=()
  local s d r ready running=0 abort=0 progressed ticker="" last_change=$SECONDS
  local heartbeat="${MIP_HEARTBEAT:-30}"

  RUN_DIR="$MIP_STATE_DIR/runs/$(date +%Y%m%d-%H%M%S)-$$"
  mkdir -p "$RUN_DIR" && ln -sfn "$RUN_DIR" "$MIP_STATE_DIR/runs/latest"
  for s in "${SELECTED[@]}"; do state[$s]=pending; done
  trap 'kill $(jobs -p) 2>/dev/null; exit 130' INT TERM

  while :; do
    # Announce background Steps that got past their Check and are now working.
    # Printed from here (not the job) so output never interleaves with an
    # Interactive Step's prompt; while one runs, these wait their turn.
    for s in "${SELECTED[@]}"; do
      if [ "${state[$s]}" != running ] || [ -n "${announced[$s]:-}" ] || [ ! -f "$RUN_DIR/$s.started" ]; then
        continue
      fi
      announced[$s]=1
      printf '▶ %-16s %s…\n' "$s" "$(cat "$RUN_DIR/$s.started")"
      last_change=$SECONDS
    done

    # Collect finished background Steps.
    for s in "${SELECTED[@]}"; do
      [ "${state[$s]}" = running ] || continue
      if [ -f "$RUN_DIR/$s.result" ]; then
        r="$(cat "$RUN_DIR/$s.result")"
      elif ! kill -0 "${pid[$s]}" 2>/dev/null; then
        r=failed   # died without recording a result
      else
        continue
      fi
      state[$s]="$r"; running=$((running - 1))
      report "$s" "$r" $((SECONDS - start[$s]))
      last_change=$SECONDS
      is_satisfied "$r" || abort=1
    done

    # Propagate blocks to Steps whose requirements can no longer be met.
    progressed=1
    while [ "$progressed" = 1 ]; do
      progressed=0
      for s in "${SELECTED[@]}"; do
        [ "${state[$s]}" = pending ] || continue
        for d in ${REQ[$s]}; do
          if is_dead "${state[$d]:-}"; then
            state[$s]=blocked; report "$s" blocked; progressed=1; break
          fi
        done
      done
    done

    # Start whatever is ready.
    progressed=0
    if [ "$abort" = 0 ]; then
      for s in "${SELECTED[@]}"; do
        [ "${state[$s]}" = pending ] || continue
        ready=1
        for d in ${REQ[$s]}; do is_satisfied "${state[$d]:-}" || { ready=0; break; }; done
        [ "$ready" = 1 ] || continue

        if is_interactive "$s"; then
          start[$s]=$SECONDS
          step_execute "$s" yes
          r="$(cat "$RUN_DIR/$s.result")"
          state[$s]="$r"; report "$s" "$r"
          is_satisfied "$r" || { [ "$r" = failed ] && abort=1; }
          progressed=1
          break   # the world changed; re-evaluate from the top
        fi

        [ "$running" -lt "$MIP_JOBS" ] || continue
        start[$s]=$SECONDS
        step_execute "$s" no </dev/null >/dev/null 2>&1 &
        pid[$s]=$!
        state[$s]=running; running=$((running + 1))
      done
    fi

    [ "$progressed" = 1 ] && continue
    [ "$running" -gt 0 ] || break
    # A 1s ticker job bounds the wait, so start lines appear promptly and long
    # silent Steps (claude-config takes minutes) get a "still running" line.
    if [ -z "$ticker" ] || ! kill -0 "$ticker" 2>/dev/null; then
      sleep 1 &
      ticker=$!
    fi
    wait -n 2>/dev/null || true
    if [ $((SECONDS - last_change)) -ge "$heartbeat" ]; then
      local busy=()
      for s in "${SELECTED[@]}"; do
        [ "${state[$s]}" = running ] && busy+=("$s ($((SECONDS - start[$s]))s)")
      done
      local joined
      joined="$(printf '%s, ' "${busy[@]}")"
      printf '… still running: %s\n' "${joined%, }"
      last_change=$SECONDS
    fi
  done
  [ -n "$ticker" ] && kill "$ticker" 2>/dev/null
  trap - INT TERM

  local failed=0 n_ok=0 n_skip=0 n_left=0
  for s in "${SELECTED[@]}"; do
    if [ "${state[$s]}" = pending ]; then state[$s]=aborted; report "$s" aborted; fi
    case "$(result_kind "${state[$s]}")" in
      ok) n_ok=$((n_ok + 1)) ;;
      skip) n_skip=$((n_skip + 1)) ;;
      fail) failed=1 ;;
      *) n_left=$((n_left + 1)) ;;
    esac
  done

  local notes=""
  for s in "${SELECTED[@]}"; do
    [ -s "$RUN_DIR/$s.note" ] && notes+="$(sed "s/^/  [$s] /" "$RUN_DIR/$s.note")"$'\n'
  done
  echo
  printf 'Run: %d ran, %d already satisfied, %d not completed%s. Logs: %s\n' \
    "$n_ok" "$n_skip" "$n_left" "$([ "$failed" = 1 ] && echo ', FAILED')" "$RUN_DIR"
  if [ -n "$notes" ]; then printf '\nNotes:\n%s' "$notes"; fi
  return "$failed"
}
