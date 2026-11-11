#!/usr/bin/env bats
# Runner behaviour against fake Actions: ordering, parallelism, skip/force,
# failure handling, interactive Steps, validation, list/describe.

load helpers

setup() { setup_pipeline; }

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

@test "--force re-runs a Step whose Check passes" {
  step a; fake_action a
  touch "$T/state/a"
  mip run --non-interactive
  [ -z "$(events)" ]
  run mip run --force a --non-interactive
  [ "$status" -eq 0 ]
  grep -q 'start a' "$T/events"
}

@test "--upgrade calls upgrade() on satisfied Steps; without one it is a skip" {
  step a; step b
  fake_action a --upgrade; fake_action b
  touch "$T/state/a" "$T/state/b"
  run mip run --upgrade --non-interactive
  [ "$status" -eq 0 ]
  [ "$(events)" = "upgrade a" ]
  [[ "$output" == *"a "*"upgraded"* ]]
  [[ "$output" == *"b "*"done"* ]]
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
  [[ "$output" == *"ask "*"todo   yes"* ]]
  MIP_ANSWER=x run mip run --dry-run
  [[ "$output" == *"ask "*"todo   no"* ]]
  MIP_ANSWER=x run mip run --non-interactive
  [ "$status" -eq 0 ]
  grep -q 'start ask tty=n' "$T/events"
  grep -q 'end needs-ask' "$T/events"
}

@test "an Interactive Step whose Check does not apply is n/a, with or without a terminal; dependents run" {
  step off; step after off
  fake_action off --interactive --na; fake_action after
  run mip run --non-interactive
  [ "$status" -eq 0 ]
  [[ "$output" == *"off "*"na"* ]] && [[ "$output" != *"deferred"* ]]
  grep -q 'end after' "$T/events"
  : >"$T/events"; rm -f "$T/state/after"
  command -v script >/dev/null || skip "util-linux script not available"
  run script -qec "$ROOT/init.sh run -y" /dev/null
  [ "$status" -eq 0 ]
  ! grep -q 'start off' "$T/events"
  grep -q 'end after' "$T/events"
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

@test "optional Interactive Step: not chosen, it is skipped without taking the terminal" {
  step x; fake_action x --optional --interactive
  run mip run --non-interactive
  [[ "$output" == *"x "*"optional"* ]] && [[ "$output" != *"deferred"* ]]
  command -v script >/dev/null || skip "util-linux script not available"
  run script -qec "$ROOT/init.sh run -y" /dev/null
  [[ "$output" == *"optional"* ]]
  ! grep -q 'start x' "$T/events"
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
  [[ "$output" == *"a "*"todo"* ]]
  [ -z "$(events)" ]
  [ ! -d "$HOME/.local/state" ]
}

@test "bad options and unknown Steps are rejected" {
  step a; fake_action a
  run mip run --bogus;     [ "$status" -ne 0 ]
  run mip run nope;        [ "$status" -ne 0 ]; [[ "$output" == *"unknown step 'nope'"* ]]
  run mip run -j 0;        [ "$status" -ne 0 ]
  run mip frobnicate;      [ "$status" -eq 2 ]
}

# ── Step picker (a terminal and no Steps named) ─────────────────────────────

picker_pipeline() {
  command -v script >/dev/null || skip "util-linux script not available"
  step base; step a base; step b; step c
  fake_action base; fake_action a; fake_action b; fake_action c
}

@test "picker: Steps with work to do start ticked; the ticked ones run with what they require" {
  picker_pipeline
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

@test "picker: a ticked Step that is already done is re-run" {
  picker_pipeline
  touch "$T/state/b"
  fake_gum 0 b
  run mip_tty run
  [ "$status" -eq 0 ]
  grep -q 'start b' "$T/events"
}

@test "picker: a ticked done Step with upgrade() is upgraded, not re-run" {
  picker_pipeline
  fake_action b --upgrade
  touch "$T/state/b"
  fake_gum 0 b
  run mip_tty run
  [ "$status" -eq 0 ]
  grep -q 'upgrade b' "$T/events"
  ! grep -q 'start b' "$T/events"
  [[ "$output" == *"↑ b"* ]]
}

@test "picker: an optional Step with work to do starts unticked, marked opt; ticking it runs it" {
  picker_pipeline
  step x; fake_action x --optional
  fake_gum 0 x
  run mip_tty run
  [ "$status" -eq 0 ]
  grep -q $'^x  *opt .*\tx$' "$T/gum.args"
  sel="$(grep -A1 -x -- '--selected' "$T/gum.args" | tail -n 1)"
  [[ "$sel" != *"x "* ]]
  grep -q 'end x' "$T/events"
}

@test "picker: cancelling runs nothing and exits 130; ticking nothing runs nothing" {
  picker_pipeline
  fake_gum 130
  run mip_tty run
  [ "$status" -eq 130 ] && [[ "$output" == *"Cancelled"* ]]
  fake_gum 0
  run mip_tty run
  [ "$status" -eq 0 ] && [[ "$output" == *"No Steps selected"* ]]
  [ ! -s "$T/events" ]
}

@test "picker: skipped with -y, named Steps, --upgrade, --dry-run, and without a terminal" {
  picker_pipeline
  fake_gum 0 c
  mip_tty run -y >/dev/null;           [ ! -e "$T/gum.args" ]
  mip_tty run b >/dev/null;            [ ! -e "$T/gum.args" ]
  mip_tty run --upgrade >/dev/null;    [ ! -e "$T/gum.args" ]
  mip_tty run --dry-run >/dev/null;    [ ! -e "$T/gum.args" ]
  mip run </dev/null >/dev/null;       [ ! -e "$T/gum.args" ]
}

@test "picker: when gum is unavailable, warns and runs every Step" {
  picker_pipeline
  run mip_tty run                          # MIP_GUM points at nothing
  [ "$status" -eq 0 ]
  [[ "$output" == *"could not show the Step picker"* ]]
  grep -q 'end c' "$T/events"
}
