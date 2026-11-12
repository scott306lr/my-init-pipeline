#!/usr/bin/env bats
# The Plan (lib/pipeline.sh step_plan): what a Run intends for one Step, as a
# table. The function reads no state, so the rules are tested here without a
# Run; tests/runner.bats covers that Runs follow them.

setup() {
  # shellcheck source=lib/pipeline.sh
  . "$BATS_TEST_DIRNAME/../lib/pipeline.sh"
}

# plans TABLE — every row "CHECK MODE UNCHOSEN INTERACTIVE TERMINAL HAS_UPGRADE => PLAN" holds.
plans() {
  local check mode unchosen interactive terminal has_upgrade arrow want got bad=0
  while read -r check mode unchosen interactive terminal has_upgrade arrow want; do
    [ -n "$check" ] || continue
    got="$(step_plan check="$check" mode="$mode" unchosen="$unchosen" interactive="$interactive" \
      terminal="$terminal" has_upgrade="$has_upgrade")"
    if [ "$got" != "$want" ]; then
      echo "$check $mode unchosen=$unchosen interactive=$interactive terminal=$terminal has_upgrade=$has_upgrade: got $got, want $want"
      bad=1
    fi
  done <<<"$1"
  return "$bad"
}

@test "a Check that does not apply is na, whatever else holds, unless the Step is forced" {
  plans "
    na    install  no  no  yes no  => na
    na    upgrade  no  no  yes yes => na
    na    install  yes no  yes no  => na
    na    install  no  yes no  no  => na
    na    force    no  no  yes no  => run
  "
}

@test "a Check that passes is done; in upgrade mode it is an upgrade when the Action has one" {
  plans "
    done  install  no  no  yes no  => done
    done  install  no  no  yes yes => done
    done  upgrade  no  no  yes no  => done
    done  upgrade  no  no  yes yes => upgrade
    done  upgrade  yes no  yes yes => upgrade
    done  install  yes no  yes no  => done
  "
}

@test "work to do runs, in install and upgrade mode alike; forced, the Check is not consulted" {
  plans "
    todo  install  no  no  yes no  => run
    todo  upgrade  no  no  yes yes => run
    todo  install  no  no  no  no  => run
    done  force    no  no  yes no  => run
    done  force    no  no  yes yes => run
    todo  force    no  no  no  no  => run
  "
}

@test "an Optional Step nobody chose is optional only while it has work to do" {
  plans "
    todo  install  yes no  yes no  => optional
    todo  upgrade  yes no  yes yes => optional
    todo  install  yes yes yes no  => optional
    todo  install  yes yes no  no  => optional
  "
}

@test "an Interactive Step with nothing to do takes no terminal: na and done are as for any Step" {
  plans "
    na    install  no  yes yes no  => na
    na    install  no  yes no  no  => na
    done  install  no  yes yes no  => done
    done  install  no  yes no  no  => done
  "
}

@test "an Interactive Step with work to do is deferred without a terminal, and runs with one" {
  plans "
    todo  install  no  yes no  no  => deferred
    todo  upgrade  no  yes no  no  => deferred
    done  force    no  yes no  no  => deferred
    todo  install  no  yes yes no  => run
    done  force    no  yes yes no  => run
  "
}

@test "an Interactive Step's upgrade needs the terminal too; without one it stays done, blocking nothing" {
  plans "
    done  upgrade  no  yes yes yes => upgrade
    done  upgrade  no  yes no  yes => done
    done  upgrade  no  yes yes no  => done
  "
}

@test "before the Check is taken, the Plan says whether it turns on it: not when the Step is forced" {
  plans "
    ?     install  no  no  yes no  => ?
    ?     upgrade  yes yes no  yes => ?
    ?     force    no  no  yes no  => run
    ?     force    no  yes no  no  => deferred
    ?     force    no  yes yes no  => run
  "
}

@test "inputs have defaults (install, Check not taken, nothing special); an unknown input is refused" {
  [ "$(step_plan)" = '?' ]
  [ "$(step_plan check=todo)" = run ]
  [ "$(step_plan check=todo interactive=yes)" = deferred ]
  [ "$(step_plan check=done mode=upgrade has_upgrade=yes)" = upgrade ]
  run step_plan chekc=todo
  [ "$status" -eq 2 ] && [[ "$output" == *"unknown input chekc=todo"* ]]
}
