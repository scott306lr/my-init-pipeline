#!/usr/bin/env bats
# Pure-logic parts of real Actions (no network): herdr hook rewrite, clone URLs.

load helpers

setup() {
  setup_pipeline
  export MIP_USER_CONFIG="$ROOT/config.sh"
  mkdir -p "$HOME/.claude" "$T/repo"
  # settings.json is a symlink into the setup repo, as claude-config leaves it.
  ln -s "$T/repo/settings.json" "$HOME/.claude/settings.json"
}

action() { bash "$ROOT/lib/step.sh" "$ROOT/actions/$1.sh" "$2"; }

settings() {  # settings ABS PORTABLE — write a SessionStart list with those hooks
  python3 - "$HOME" "$1" "$2" >"$T/repo/settings.json" <<'PY'
import json, sys
home, want_abs, want_portable = sys.argv[1], sys.argv[2] == "1", sys.argv[3] == "1"
hook = lambda c: {"matcher": "*", "hooks": [{"type": "command", "command": c, "timeout": 10}]}
groups = [hook("echo unrelated")]
if want_portable:
    groups.append(hook('bash "$HOME/.claude/hooks/herdr-agent-state.sh" session 2>/dev/null || true'))
if want_abs:
    groups.append(hook(f"bash '{home}/.claude/hooks/herdr-agent-state.sh' session"))
print(json.dumps({"model": "x", "hooks": {"SessionStart": groups}}, indent=2))
PY
}

session_commands() {
  python3 -c "import json,sys; [print(h['command']) for g in json.load(open(sys.argv[1]))['hooks']['SessionStart'] for h in g['hooks']]" "$HOME/.claude/settings.json"
}

@test "herdr: absolute hook is dropped when the portable one exists; symlink and others kept" {
  settings 1 1
  run action herdr-install portable_hooks
  [ "$status" -eq 0 ]
  [ -L "$HOME/.claude/settings.json" ]
  run session_commands
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "echo unrelated" ]
  [[ "${lines[1]}" == 'bash "$HOME/'* ]]
}

@test "herdr: a lone absolute hook is rewritten to the \$HOME form" {
  settings 1 0
  action herdr-install portable_hooks
  run session_commands
  [ "${lines[1]}" = 'bash "$HOME/.claude/hooks/herdr-agent-state.sh" session' ]
  ! grep -q "$HOME" "$T/repo/settings.json"
}

@test "herdr: --check fails only while a machine-specific hook is present; clean file untouched" {
  settings 1 1
  # step.sh calls a function by name only, so reach --check through a wrapper Action.
  printf '. %q\ncheck_hooks() { portable_hooks --check; }\n' "$ROOT/actions/herdr-install.sh" >"$T/wrap.sh"
  run bash "$ROOT/lib/step.sh" "$T/wrap.sh" check_hooks
  [ "$status" -eq 1 ]
  action herdr-install portable_hooks
  run bash "$ROOT/lib/step.sh" "$T/wrap.sh" check_hooks
  [ "$status" -eq 0 ]
  before="$(stat -c %Y.%s "$T/repo/settings.json")"; sleep 1
  action herdr-install portable_hooks
  [ "$(stat -c %Y.%s "$T/repo/settings.json")" = "$before" ]
}

@test "claude-config: clone URL follows CLAUDE_SETUP_PROTOCOL" {
  run env CLAUDE_SETUP_PROTOCOL=https bash "$ROOT/lib/step.sh" "$ROOT/actions/claude-config.sh" clone_url
  [ "$output" = "https://github.com/scott306lr/my-claude-setup.git" ]
  run env CLAUDE_SETUP_PROTOCOL=ssh CLAUDE_SETUP_REPO=me/x bash "$ROOT/lib/step.sh" "$ROOT/actions/claude-config.sh" clone_url
  [ "$output" = "git@github.com:me/x.git" ]
  run env CLAUDE_SETUP_PROTOCOL=ftp bash "$ROOT/lib/step.sh" "$ROOT/actions/claude-config.sh" clone_url
  [ "$status" -ne 0 ]
  [[ "$output" == *"must be https or ssh"* ]]
}

@test "delta: sets git's pager only when none is configured" {
  mkdir -p "$T/bin"; printf '#!/bin/sh\necho delta 0.0\n' >"$T/bin/delta"; chmod +x "$T/bin/delta"
  PATH="$T/bin:$PATH" action delta-install run
  [ "$(git config --global --get core.pager)" = delta ]
  [ "$(git config --global --get interactive.diffFilter)" = "delta --color-only" ]

  git config --global core.pager less
  PATH="$T/bin:$PATH" action delta-install run
  [ "$(git config --global --get core.pager)" = less ]
  PATH="$T/bin:$PATH" action delta-install check
}
