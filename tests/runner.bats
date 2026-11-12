#!/usr/bin/env bats
# Runs against fake Actions: scheduling (order, parallelism, heartbeat, abort),
# one Run per kind of outcome, the dry run, Notes, the checklist, validation,
# list/describe. The rules for a Step's Plan are a table in tests/plan.bats.

load helpers

setup() { setup_pipeline; }

# plan_of STEP — STEP's PLAN column in the dry run held by $output.
plan_of() { awk -v s="$1" '$1 == s { print $2 }' <<<"$output"; }

@test "runs Steps in dependency order, not file order" {
  step c b; step b a; step a
  for s in a b c; do fake_action $s; done
  run mip run --non-interactive
  [ "$status" -eq 0 ]
  [ "$(grep -c '^start' "$T/events")" -eq 3 ]
  [ "$(line_of 'end a')" -lt "$(line_of 'start b')" ]
  [ "$(line_of 'end b')" -lt "$(line_of 'start c')" ]
}

@test "second Run skips every Step whose Check passes" {
  step a; step b a
  fake_action a; fake_action b
  mip run --non-interactive
  : >"$T/events"
  run mip run --non-interactive
  [ "$status" -eq 0 ]
  [ -z "$(events)" ]
  [[ "$output" == *"= a "*"done"* ]]
  [[ "$output" == *"0 ran, 2 already satisfied"* ]]
}

@test "independent Steps run in parallel; -j 1 runs them serially" {
  step x; step y
  fake_action x --sleep 1; fake_action y --sleep 1
  mip run -j 2 --non-interactive
  [ "$(line_of 'start y')" -lt "$(line_of 'end x')" ]

  rm -f "$T"/state/*; : >"$T/events"
  mip run -j 1 --non-interactive
  [ "$(line_of 'end x')" -lt "$(line_of 'start y')" ]
}

@test "a failure blocks dependents, starts nothing new, and exits 1" {
  step a; step b a; step c
  fake_action a --fail; fake_action b; fake_action c
  run mip run -j 1 --non-interactive
  [ "$status" -eq 1 ]
  [[ "$output" == *"✗ a "*"failed"*"log: "* ]]
  [[ "$output" == *"b "*"blocked"* ]]
  [[ "$output" == *"c "*"aborted"* ]]
  ! grep -q 'start c' "$T/events"
  grep -q 'boom from a' "$HOME/.local/state/my-init-pipeline/runs/latest/a.log"
}

@test "the summary counts each Step once: a failed one is not 'not completed', an aborted one counts once" {
  step a; step b a; step c
  fake_action a --fail; fake_action b; fake_action c
  run mip run -j 1 --non-interactive
  [ "$status" -eq 1 ]
  [[ "$output" == *"Run: 0 ran, 0 already satisfied, 2 not completed, FAILED."* ]]
}

@test "a Check that still fails after run marks the Step failed" {
  step a
  fake_action a --stays-unsatisfied
  run mip run --non-interactive
  [ "$status" -eq 1 ]
  grep -q 'check still fails after run' "$HOME/.local/state/my-init-pipeline/runs/latest/a.log"
}

@test "Check exit 2 means not applicable: skipped, dependents still run" {
  step gpu; step after gpu
  fake_action gpu --na; fake_action after
  run mip run --non-interactive
  [ "$status" -eq 0 ]
  [[ "$output" == *"- gpu "*"na"* ]]
  grep -q 'end after' "$T/events"
}

@test "naming a Step runs it plus what it requires, nothing else" {
  step a; step b a; step c
  for s in a b c; do fake_action $s; done
  run mip run b --non-interactive
  [ "$status" -eq 0 ]
  grep -q 'end a' "$T/events"; grep -q 'end b' "$T/events"
  ! grep -q 'start c' "$T/events"
}

@test "non-interactive: unsatisfied Interactive Step is deferred and blocks dependents only" {
  step login
  step needs-login login; step other
  fake_action login --interactive; fake_action needs-login; fake_action other
  run mip run --non-interactive
  [ "$status" -eq 0 ]
  [[ "$output" == *"login "*"deferred"* ]]
  [[ "$output" == *"needs-login "*"blocked"* ]]
  grep -q 'end other' "$T/events"
  ! grep -q 'start login' "$T/events"
}

@test "non-interactive: an Interactive Step whose setting answers its prompt runs; unanswered it is deferred" {
  step ask; step needs-ask ask
  fake_action ask --answered-by MIP_ANSWER; fake_action needs-ask
  run mip run --non-interactive
  [[ "$output" == *"ask "*"deferred"* ]]
  run mip run --dry-run
  [[ "$output" == *"ask "*"deferred"* ]]
  MIP_ANSWER=x run mip run --dry-run
  [[ "$output" == *"ask "*"run"* ]]
  MIP_ANSWER=x run mip run --non-interactive
  [ "$status" -eq 0 ]
  grep -q 'start ask tty=n' "$T/events"
  grep -q 'end needs-ask' "$T/events"
}

@test "optional: skipped (not run) unless named or forced; done shows done; what requires it still runs" {
  step x; step after x; step other
  fake_action x --optional; fake_action after; fake_action other
  run mip run -y
  [ "$status" -eq 0 ]
  [[ "$output" == *"○ x "*"optional; to run it: ./init.sh run x"* ]]
  ! grep -q 'start x' "$T/events"
  grep -q 'end after' "$T/events" && grep -q 'end other' "$T/events"
  run mip run x --non-interactive            # named: runs
  grep -q 'end x' "$T/events"
  run mip run -y
  [[ "$output" == *"= x "*"done"* ]]
  rm "$T/state/x"; : >"$T/events"
  run mip run --force x --non-interactive    # forced: runs
  grep -q 'end x' "$T/events"
}

@test "non-interactive: satisfied Interactive Step counts as done" {
  step login; step needs-login login
  fake_action login --interactive; fake_action needs-login
  touch "$T/state/login"
  run mip run --non-interactive
  [ "$status" -eq 0 ]
  grep -q 'end needs-login' "$T/events"
}

@test "no terminal on stdin implies non-interactive" {
  step login; fake_action login --interactive
  run mip run </dev/null
  [[ "$output" == *"No terminal attached"* ]]
  [[ "$output" == *"deferred"* ]]
}

@test "with a terminal, Interactive Step gets the tty; dependents wait, others overlap" {
  command -v script >/dev/null || skip "util-linux script not available"
  step bg; step login; step needs-login login
  fake_action bg --sleep 2; fake_action login --interactive --sleep 1; fake_action needs-login
  run script -qec "$ROOT/init.sh run -y -j 4" /dev/null
  [ "$status" -eq 0 ]
  grep -q 'start login tty=y' "$T/events"
  grep -q 'start bg tty=n' "$T/events"
  [ "$(line_of 'end login')" -lt "$(line_of 'start needs-login')" ]
  [ "$(line_of 'start login')" -lt "$(line_of 'end bg')" ]
}

@test "a long silent Step gets periodic 'still running' lines" {
  step slow; step quick
  fake_action slow --sleep 4; fake_action quick
  MIP_HEARTBEAT=1 run mip run --non-interactive
  [ "$status" -eq 0 ]
  [[ "$output" == *"… still running: slow ("*"s)"* ]]
  [[ "$output" != *"still running: quick"* ]]
}

@test "a Step that has work to do is announced before it finishes; satisfied ones are not" {
  step a; step b
  fake_action a --sleep 2; fake_action b
  touch "$T/state/b"
  run mip run --non-interactive
  [ "$status" -eq 0 ]
  started="$(grep -n '▶ a .*installing' <<<"$output" | cut -d: -f1)"
  finished="$(grep -n '✓ a ' <<<"$output" | cut -d: -f1)"
  [ -n "$started" ] && [ "$started" -lt "$finished" ]
  [[ "$output" != *"▶ b "* ]]
}

@test "an upgrade() that fails with status 3 fails the Step; it is not read as 'no upgrade()'" {
  step a
  printf '%s\n' '# summary: a' 'check() { :; }' 'run() { :; }' 'upgrade() { return 3; }' >"$MIP_ACTIONS_DIR/a.sh"
  run mip run --upgrade --non-interactive
  [ "$status" -eq 1 ]
  [[ "$output" == *"a "*"failed"* ]]
}

@test "lib/step.sh: a function the Action lacks is status 127; --defines says whether it has one" {
  fake_action a --upgrade
  run -127 bash "$ROOT/lib/step.sh" "$MIP_ACTIONS_DIR/a.sh" note
  [[ "$output" == *"defines no note()"* ]]
  bash "$ROOT/lib/step.sh" "$MIP_ACTIONS_DIR/a.sh" --defines upgrade
  run bash "$ROOT/lib/step.sh" "$MIP_ACTIONS_DIR/a.sh" --defines note
  [ "$status" -eq 1 ]
}

@test "notes: a note() that fails is logged and does not fail the Step" {
  step a
  printf '%s\n' '# summary: a' 'check() { [ -f "$T/state/a" ]; }' 'run() { touch "$T/state/a"; }' \
    'note() { echo "broken note" >&2; return 1; }' >"$MIP_ACTIONS_DIR/a.sh"
  run mip run --non-interactive
  [ "$status" -eq 0 ] && [[ "$output" == *"✓ a "* ]]
  grep -q 'broken note' "$HOME/.local/state/my-init-pipeline/runs/latest/a.log"
  grep -q 'note() failed' "$HOME/.local/state/my-init-pipeline/runs/latest/a.log"
}

@test "an Action file that cannot be loaded fails its Step with the reason in the log, Interactive or not" {
  step broken; step other
  printf '%s\n' '# summary: broken' '# interactive: yes' 'no-such-command-here' 'check() { :; }' 'run() { :; }' >"$MIP_ACTIONS_DIR/broken.sh"
  fake_action other
  run bash "$ROOT/lib/step.sh" "$MIP_ACTIONS_DIR/broken.sh" --defines check
  [ "$status" -eq 126 ]
  run mip run -j 1 --non-interactive
  [ "$status" -eq 1 ]
  [[ "$output" == *"✗ broken "*"failed"* ]] && [[ "$output" != *"deferred"* ]]
  grep -q 'no-such-command-here' "$HOME/.local/state/my-init-pipeline/runs/latest/broken.log"
}

@test "a forced Step's Check is not taken, in a Run or a dry run" {
  step a
  printf '%s\n' '# summary: a' 'check() { echo checked >>"$T/events"; }' 'run() { echo ran >>"$T/events"; }' >"$MIP_ACTIONS_DIR/a.sh"
  run mip run --force a --dry-run
  [ "$(plan_of a)" = run ] && [ -z "$(events)" ]
  mip run --force a --non-interactive
  [ "$(events)" = "$(printf 'ran\nchecked')" ]   # only the Check after run()
}

@test "--upgrade announces upgrading" {
  step a; fake_action a --upgrade
  touch "$T/state/a"
  run mip run --upgrade --non-interactive
  [[ "$output" == *"▶ a"*"upgrading…"* ]]
}

@test "no heartbeat when Steps finish within the interval" {
  step a; fake_action a
  MIP_HEARTBEAT=5 run mip run --non-interactive
  [[ "$output" != *"still running"* ]]
}

@test "PATH hint: shown when the run adds PATH entries the calling shell lacks" {
  step p
  printf 'check() { env_has_path "\\$HOME/tools"; }\nrun() { add_path "\\$HOME/tools"; }\n' >"$MIP_ACTIONS_DIR/p.sh"
  run mip run --non-interactive
  [ "$status" -eq 0 ]
  [[ "$output" == *"Shell setup changed."*"source ~/.bashrc"* ]]

  # Same state, but the calling shell already has the entry: no hint.
  PATH="$HOME/tools:$PATH" run mip run --non-interactive
  [[ "$output" != *"Shell setup changed."* ]]
}

@test "shell hint: shown when the run adds a shell hook (no PATH change)" {
  step h
  printf 'check() { env_has_shell_init "alias zz=true"; }\nrun() { add_shell_init "alias zz=true"; }\n' >"$MIP_ACTIONS_DIR/h.sh"
  run mip run --non-interactive
  [[ "$output" == *"Shell setup changed."* ]]
  run mip run --non-interactive
  [[ "$output" != *"Shell setup changed."* ]]
}

@test "PATH hint: absent when nothing touches PATH" {
  step a; fake_action a
  run mip run --non-interactive
  [[ "$output" != *"Shell setup changed."* ]]
}

@test "notes from Steps that ran are printed at the end" {
  step a; fake_action a --note "please log in"
  run mip run --non-interactive
  [[ "$output" == *"Notes:"*"[a] please log in"* ]]
  run mip run --non-interactive
  [[ "$output" != *"Notes:"* ]]
}

@test "notes: note() gets the result word, after an upgrade too" {
  step a
  printf '%s\n' 'check() { [ -f "$T/state/a" ]; }' 'run() { touch "$T/state/a"; }' \
    'upgrade() { :; }' 'note() { echo "note after $1"; }' >"$MIP_ACTIONS_DIR/a.sh"
  run mip run --non-interactive
  [[ "$output" == *"[a] note after ran"* ]]
  run mip run --upgrade --non-interactive
  [[ "$output" == *"[a] note after upgraded"* ]]
}

@test "update: fast-forwards the checkout, then runs the given command with it" {
  git -C "$T" init -q -b main origin
  cp -r "$ROOT/init.sh" "$ROOT/lib" "$T/origin/"
  git -C "$T/origin" add -A && git -C "$T/origin" -c user.name=t -c user.email=t@t commit -qm one
  git clone -q "$T/origin" "$T/mip"
  echo x >"$T/origin/new" && git -C "$T/origin" add new && git -C "$T/origin" -c user.name=t -c user.email=t@t commit -qm two
  step a; fake_action a
  run "$T/mip/init.sh" update list
  [ "$status" -eq 0 ]
  [[ "$output" == *"my-init-pipeline: "*" two"* ]]
  [[ "$output" == *"fake a"* ]]                       # `list` ran after the pull
  [ -f "$T/mip/new" ]
  run "$T/mip/init.sh" update                          # up to date, no command
  [ "$status" -eq 0 ]
  echo y >"$T/mip/new"; git -C "$T/mip" -c user.name=t -c user.email=t@t commit -qam local
  echo z >"$T/origin/new"; git -C "$T/origin" -c user.name=t -c user.email=t@t commit -qam three
  run "$T/mip/init.sh" update list
  [ "$status" -ne 0 ] && [[ "$output" == *"could not fast-forward"* ]] && [[ "$output" != *"fake a"* ]]
}

@test "validation: unknown requirement, cycle, missing action, duplicate" {
  step a nope; fake_action a
  run mip run --non-interactive
  [ "$status" -eq 2 ]; [[ "$output" == *"requires unknown step 'nope'"* ]]

  : >"$MIP_CONF"; step a b; step b a; fake_action b
  run mip list
  [ "$status" -eq 2 ]; [[ "$output" == *"dependency cycle among: a b"* ]]

  : >"$MIP_CONF"; step ghost
  run mip list
  [ "$status" -eq 2 ]; [[ "$output" == *"no action file"* ]]

  : >"$MIP_CONF"; step a; step a
  run mip list
  [ "$status" -eq 2 ]; [[ "$output" == *"defined twice"* ]]
}

@test "conf: comments, blank lines, and a different action name per Step" {
  printf '# header\n\nfirst  shared   # trailing comment\nsecond shared first\n' >"$MIP_CONF"
  fake_action shared
  run mip list
  [ "$status" -eq 0 ]
  [[ "$output" == *"first           shared"* ]]
  [[ "$output" == *"second          shared           first"* ]]
}

@test "list and describe show the mapping, requires, required-by and header" {
  step a; step b a
  fake_action a; fake_action b
  run mip list
  [[ "$output" == *"b               b                a                        todo   fake b"* ]]
  run mip describe a
  [ "$status" -eq 0 ]
  [[ "$output" == *"required by: b"* ]]
  [[ "$output" == *"summary: fake a"* ]]
  run mip describe nope
  [ "$status" -ne 0 ]
}

@test "dry run reports the plan and changes nothing" {
  step a; step b a; fake_action a; fake_action b
  run mip run b --dry-run
  [ "$status" -eq 0 ]
  [ "$(plan_of a)" = run ] && [ "$(plan_of b)" = run ]
  [ -z "$(events)" ]
  [ ! -d "$HOME/.local/state" ]
}

@test "dry run prints what the Run would do to each Step, as the Run then does" {
  step ran; step isdone; step up; step off; step opt; step login; step forced
  fake_action ran; fake_action isdone; fake_action up --upgrade; fake_action off --na
  fake_action opt --optional; fake_action login --interactive; fake_action forced
  touch "$T/state/isdone" "$T/state/up" "$T/state/forced"
  run mip run --upgrade --force forced --dry-run
  [ "$(plan_of ran)" = run ] && [ "$(plan_of isdone)" = "done" ] && [ "$(plan_of up)" = upgrade ]
  [ "$(plan_of off)" = na ] && [ "$(plan_of opt)" = optional ] && [ "$(plan_of login)" = deferred ]
  [ "$(plan_of forced)" = run ]
  run mip run --upgrade --force forced --non-interactive
  [[ "$output" == *"✓ ran "* && "$output" == *"= isdone "* && "$output" == *"↑ up "* && "$output" == *"- off "* ]]
  [[ "$output" == *"○ opt "* && "$output" == *"⏸ login "* && "$output" == *"✓ forced "* ]]
  # Only the upgrade, the Step with work to do and the forced one did anything.
  [ "$(events | sort)" = "$(printf '%s\n' 'upgrade up' 'start ran tty=n' 'end ran' 'start forced tty=n' 'end forced' | sort)" ]
}

@test "an Interactive Step is upgraded on a terminal; without one its upgrade is skipped and nothing is blocked" {
  step login; step after login
  fake_action login --interactive --upgrade; fake_action after
  touch "$T/state/login"
  run mip run --upgrade --non-interactive
  [ "$status" -eq 0 ]
  [[ "$output" == *"= login "*"done"* ]] && grep -q 'end after' "$T/events"
  command -v script >/dev/null || skip "util-linux script not available"
  run script -qec "$ROOT/init.sh run --upgrade" /dev/null
  [[ "$output" == *"↑ login "*"upgraded"* ]]
  grep -q 'upgrade login' "$T/events"
}

@test "bad options and unknown Steps are rejected" {
  step a; fake_action a
  run mip run --bogus;     [ "$status" -ne 0 ]
  run mip run nope;        [ "$status" -ne 0 ]; [[ "$output" == *"unknown step 'nope'"* ]]
  run mip run -j 0;        [ "$status" -ne 0 ]
  run mip frobnicate;      [ "$status" -eq 2 ]
}

# ── checklist (a terminal and no Steps named) ─────────────────────────────

checklist_pipeline() {
  command -v script >/dev/null || skip "util-linux script not available"
  step base; step a base; step b; step c
  fake_action base; fake_action a; fake_action b; fake_action c
}

@test "checklist: Steps with work to do start ticked; the ticked ones run with what they require" {
  checklist_pipeline
  touch "$T/state/b"                       # b is done
  fake_gum 0 a
  run mip_tty run
  [ "$status" -eq 0 ]
  grep -qx -- '--no-limit' "$T/gum.args"
  # --selected lists a, base and c (todo), not b (done).
  sel="$(grep -A1 -x -- '--selected' "$T/gum.args" | tail -n 1)"
  [[ "$sel" == *"base "* && "$sel" == *"a "* && "$sel" == *"c "* && "$sel" != *"b "* ]]
  grep -q $'^b  *done .*\tb$' "$T/gum.args"
  grep -q 'end base' "$T/events" && grep -q 'end a' "$T/events"
  ! grep -q 'start c' "$T/events"
}

@test "checklist: a ticked Step that is already done is re-run" {
  checklist_pipeline
  touch "$T/state/b"
  fake_gum 0 b
  run mip_tty run
  [ "$status" -eq 0 ]
  grep -q 'start b' "$T/events"
}

@test "checklist: a ticked done Step with upgrade() is upgraded, not re-run" {
  checklist_pipeline
  fake_action b --upgrade
  touch "$T/state/b"
  fake_gum 0 b
  run mip_tty run
  [ "$status" -eq 0 ]
  grep -q 'upgrade b' "$T/events"
  ! grep -q 'start b' "$T/events"
  [[ "$output" == *"↑ b"* ]]
}

@test "checklist: an optional Step with work to do starts unticked, marked opt; ticking it runs it" {
  checklist_pipeline
  step x; fake_action x --optional
  fake_gum 0 x
  run mip_tty run
  [ "$status" -eq 0 ]
  grep -q $'^x  *opt .*\tx$' "$T/gum.args"
  sel="$(grep -A1 -x -- '--selected' "$T/gum.args" | tail -n 1)"
  [[ "$sel" != *"x "* ]]
  grep -q 'end x' "$T/events"
}

@test "checklist: cancelling runs nothing and exits 130; ticking nothing runs nothing" {
  checklist_pipeline
  fake_gum 130
  run mip_tty run
  [ "$status" -eq 130 ] && [[ "$output" == *"Cancelled"* ]]
  fake_gum 0
  run mip_tty run
  [ "$status" -eq 0 ] && [[ "$output" == *"No Steps selected"* ]]
  [ ! -s "$T/events" ]
}

@test "checklist: skipped with -y, named Steps, --upgrade, --dry-run, and without a terminal" {
  checklist_pipeline
  fake_gum 0 c
  mip_tty run -y >/dev/null;           [ ! -e "$T/gum.args" ]
  mip_tty run b >/dev/null;            [ ! -e "$T/gum.args" ]
  mip_tty run --upgrade >/dev/null;    [ ! -e "$T/gum.args" ]
  mip_tty run --dry-run >/dev/null;    [ ! -e "$T/gum.args" ]
  mip run </dev/null >/dev/null;       [ ! -e "$T/gum.args" ]
}

@test "checklist: when gum is unavailable, warns and runs every Step" {
  checklist_pipeline
  run mip_tty run                          # MIP_GUM points at nothing
  [ "$status" -eq 0 ]
  [[ "$output" == *"could not show the checklist"* ]]
  grep -q 'end c' "$T/events"
}
