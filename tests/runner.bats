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
  run script -qec "$ROOT/init.sh run -j 4" /dev/null
  [ "$status" -eq 0 ]
  grep -q 'start login tty=y' "$T/events"
  grep -q 'start bg tty=n' "$T/events"
  [ "$(line_of 'end login')" -lt "$(line_of 'start needs-login')" ]
  [ "$(line_of 'start login')" -lt "$(line_of 'end bg')" ]
}

@test "notes from Steps that ran are printed at the end" {
  step a; fake_action a --note "please log in"
  run mip run --non-interactive
  [[ "$output" == *"Notes:"*"[a] please log in"* ]]
  run mip run --non-interactive
  [[ "$output" != *"Notes:"* ]]
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
