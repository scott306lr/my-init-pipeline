# Pipeline model and scheduler. Sourced by init.sh; expects MIP_ROOT, MIP_CONF
# and MIP_ACTIONS_DIR to be set and lib/common.sh to be loaded.
#
# Step results:
#   ran       Check failed, Action ran, Check passed afterwards
#   upgraded  --upgrade: Check passed and the Action's upgrade() ran
#   done      Check already passed — skipped
#   na        Check reported "not applicable here" (exit 2) — skipped
#   failed    Action or post-run Check failed
#   deferred  Interactive Step in a non-interactive Run
#   blocked   A required Step failed, was deferred, or was blocked
#   aborted   Not started because another Step failed

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

# ── action headers ────────────────────────────────────────────────────────────

# action_header STEP — the leading comment block of the Step's Action file.
action_header() {
  awk 'NR==1 && /^#!/ {next} /^#/ {sub(/^# ?/, ""); print; next} {exit}' "$(action_file "$1")"
}

# action_field STEP FIELD — value of "# FIELD: value" in the header, if any.
action_field() {
  action_header "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -n 1
}

is_interactive() { [ "$(action_field "$1" interactive)" = yes ]; }

# ── execution ─────────────────────────────────────────────────────────────────

step_call() { bash "$MIP_ROOT/lib/step.sh" "$(action_file "$1")" "$2"; }

# check_status STEP — prints done | na | todo (Checks must have no side effects).
check_status() {
  local rc=0
  step_call "$1" check >/dev/null 2>&1 || rc=$?
  case "$rc" in 0) echo "done" ;; 2) echo na ;; *) echo todo ;; esac
}

# step_execute STEP FORCE — the body of one Step. Prints its result word last.
# Output (other than the result) is meant for the Step's log.
step_execute() {
  local step="$1" force="$2" rc=0
  echo "== $step (action: ${ACTION[$step]}) $(date '+%F %T')"
  if [ "$force" != 1 ]; then
    echo "-- check"
    step_call "$step" check || rc=$?
    if [ "$rc" = 2 ]; then echo "RESULT na"; return; fi
    if [ "$rc" = 0 ]; then
      if [ "$MIP_MODE" = upgrade ]; then
        echo "-- upgrade"
        rc=0; step_call "$step" upgrade || rc=$?
        case "$rc" in
          0) echo "RESULT upgraded" ;;
          3) echo "RESULT done" ;;   # Action has no upgrade()
          *) echo "RESULT failed" ;;
        esac
      else
        echo "RESULT done"
      fi
      return
    fi
  fi
  echo "-- run"
  if ! step_call "$step" run; then echo "RESULT failed"; return; fi
  echo "-- check (after run)"
  if ! step_call "$step" check; then
    echo "check still fails after run"
    echo "RESULT failed"
    return
  fi
  echo "RESULT ran"
}

# Background job wrapper: log everything, leave the result in a file.
step_job() {
  local step="$1" force="$2" out
  out="$(step_execute "$step" "$force" 2>&1 | tee -a "$RUN_DIR/$step.log" | sed -n 's/^RESULT //p' | tail -n 1)"
  [ "$out" = ran ] && { step_call "$step" note >"$RUN_DIR/$step.note" 2>/dev/null || true; }
  printf '%s\n' "${out:-failed}" >"$RUN_DIR/$step.result"
}

# Interactive Steps own the terminal: no redirection, so prompts and tty
# detection work. Only the runner's own bookkeeping goes to the log.
step_foreground() {
  local step="$1" force="$2" rc=0 result
  echo "== $step (interactive) $(date '+%F %T')" >>"$RUN_DIR/$step.log"
  if [ "$force" != 1 ] && [ "$(check_status "$step")" = "done" ]; then
    result="done"
  else
    printf '▶ %s (interactive)\n' "$step"
    step_call "$step" run </dev/tty || rc=$?
    if [ "$rc" = 0 ] && [ "$(check_status "$step")" = "done" ]; then
      result=ran
      step_call "$step" note >"$RUN_DIR/$step.note" 2>/dev/null || true
    else
      result=failed
    fi
  fi
  echo "RESULT $result" >>"$RUN_DIR/$step.log"
  printf '%s\n' "$result" >"$RUN_DIR/$step.result"
}

report() {
  local step="$1" result="$2" secs="${3:-}" mark extra=""
  case "$result" in
    ran) mark="✓" ;;  upgraded) mark="↑" ;;  done) mark="=" ;;  na) mark="-" ;;
    failed) mark="✗"; extra="  log: $RUN_DIR/$step.log" ;;
    deferred) mark="⏸"; extra="  (interactive; rerun with a terminal)" ;;
    *) mark="⊘" ;;
  esac
  [ -n "$secs" ] && secs="${secs}s"
  printf '%s %-16s %-9s %5s%s\n' "$mark" "$step" "$result" "$secs" "$extra"
}

is_satisfied() { case "$1" in ran | upgraded | done | na) return 0 ;; esac; return 1; }
is_dead() { case "$1" in failed | deferred | blocked | aborted) return 0 ;; esac; return 1; }

# pipeline_run STEP... — schedule the given (already selected, TOPO-ordered)
# Steps. Uses MIP_JOBS, MIP_INTERACTIVE (0/1), MIP_MODE, and FORCE[step].
# Returns 1 if any Step failed.
pipeline_run() {
  local -a plan=("$@")
  local -A state=() pid=() start=()
  local s d r ready running=0 abort=0 progressed

  for s in "${plan[@]}"; do state[$s]=pending; done
  trap 'kill $(jobs -p) 2>/dev/null; exit 130' INT TERM

  while :; do
    # Collect finished background Steps.
    for s in "${plan[@]}"; do
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
      is_satisfied "$r" || abort=1
    done

    # Propagate blocks to Steps whose requirements can no longer be met.
    progressed=1
    while [ "$progressed" = 1 ]; do
      progressed=0
      for s in "${plan[@]}"; do
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
      for s in "${plan[@]}"; do
        [ "${state[$s]}" = pending ] || continue
        ready=1
        for d in ${REQ[$s]}; do is_satisfied "${state[$d]:-}" || { ready=0; break; }; done
        [ "$ready" = 1 ] || continue

        if is_interactive "$s"; then
          if [ "$MIP_INTERACTIVE" != 1 ]; then
            if [ "${FORCE[$s]:-0}" != 1 ] && [ "$(check_status "$s")" = "done" ]; then r="done"; else r=deferred; fi
          else
            start[$s]=$SECONDS
            step_foreground "$s" "${FORCE[$s]:-0}"
            r="$(cat "$RUN_DIR/$s.result")"
          fi
          state[$s]="$r"; report "$s" "$r"
          is_satisfied "$r" || { [ "$r" = failed ] && abort=1; }
          progressed=1
          break   # the world changed; re-evaluate from the top
        fi

        [ "$running" -lt "$MIP_JOBS" ] || continue
        start[$s]=$SECONDS
        step_job "$s" "${FORCE[$s]:-0}" </dev/null >/dev/null 2>&1 &
        pid[$s]=$!
        state[$s]=running; running=$((running + 1))
      done
    fi

    [ "$progressed" = 1 ] && continue
    [ "$running" -gt 0 ] || break
    wait -n 2>/dev/null || true
  done
  trap - INT TERM

  local failed=0 n_ok=0 n_skip=0 n_left=0
  for s in "${plan[@]}"; do
    case "${state[$s]}" in
      pending) state[$s]=aborted; report "$s" aborted; n_left=$((n_left + 1)) ;;
    esac
    case "${state[$s]}" in
      ran | upgraded) n_ok=$((n_ok + 1)) ;;
      done | na) n_skip=$((n_skip + 1)) ;;
      failed) failed=1 ;;
      *) n_left=$((n_left + 1)) ;;
    esac
  done

  local notes=""
  for s in "${plan[@]}"; do
    [ -s "$RUN_DIR/$s.note" ] && notes+="$(sed "s/^/  [$s] /" "$RUN_DIR/$s.note")"$'\n'
  done
  echo
  printf 'Run: %d ran, %d already satisfied, %d not completed%s. Logs: %s\n' \
    "$n_ok" "$n_skip" "$n_left" "$([ "$failed" = 1 ] && echo ', FAILED')" "$RUN_DIR"
  if [ -n "$notes" ]; then printf '\nNotes:\n%s' "$notes"; fi
  return "$failed"
}
