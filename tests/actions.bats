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

@test "git-identity: sets only the unset half of the identity, keeps a hand-set one" {
  run action git-identity check
  [ "$status" -eq 1 ]
  git config --global user.email me@example.com
  GIT_USER_NAME="Some One" GIT_USER_EMAIL=ignored@example.com action git-identity run
  [ "$(git config --global --get user.name)" = "Some One" ]
  [ "$(git config --global --get user.email)" = me@example.com ]
  action git-identity check
}

@test "git-identity: an empty setting fails loudly instead of writing nothing" {
  # An empty environment override falls back to config.sh's default, so blank it there.
  printf 'GIT_USER_NAME=Some\nGIT_USER_EMAIL=\n' >"$T/config.sh"
  run env MIP_USER_CONFIG="$T/config.sh" bash "$ROOT/lib/step.sh" "$ROOT/actions/git-identity.sh" run
  [ "$status" -ne 0 ]
  [[ "$output" == *"GIT_USER_EMAIL"* ]]
  [ "$(git config --global --get user.name)" = Some ]
  [ -z "$(git config --global --get user.email)" ]
}

ENV_SH='$HOME/.config/my-init-pipeline/env.sh'
hf_exports() { grep -c '^export HF_HOME=' "$HOME/.config/my-init-pipeline/env.sh"; }

@test "hf-home: HF_HOME_DIR set — no prompt; a changed setting fails the Check and is re-pointed" {
  run action hf-home check
  [ "$status" -eq 1 ]
  HF_HOME_DIR="$HOME/hf" action hf-home run </dev/null
  [ -d "$HOME/hf" ]
  grep -qxF 'export HF_HOME="$HOME/hf"' "$HOME/.config/my-init-pipeline/env.sh"
  HF_HOME_DIR="$HOME/hf" action hf-home check
  action hf-home check                       # unset setting: the recorded one is fine
  run bash -c ". $ENV_SH; echo \"\$HF_HOME\""
  [ "$output" = "$HOME/hf" ]

  run env HF_HOME_DIR="$T/data/hf" bash "$ROOT/lib/step.sh" "$ROOT/actions/hf-home.sh" check
  [ "$status" -eq 1 ]
  HF_HOME_DIR="$T/data/hf" action hf-home run </dev/null
  [ "$(hf_exports)" -eq 1 ]
  grep -qxF "export HF_HOME=\"$T/data/hf\"" "$HOME/.config/my-init-pipeline/env.sh"
  HF_HOME_DIR="$T/data/hf" action hf-home check
}

@test "hf-home: HF_HOME_DIR empty — prompts; Enter keeps the recorded value; ~ expands; relative is refused" {
  printf 'HF_HOME_DIR=\n' >"$T/config.sh"
  hf() { MIP_USER_CONFIG="$T/config.sh" bash "$ROOT/lib/step.sh" "$ROOT/actions/hf-home.sh" "$1"; }
  run hf check
  [ "$status" -eq 1 ]                        # not na: a human can answer it
  run hf run </dev/null                      # no terminal and nothing recorded: default applies
  [ "$status" -eq 0 ]
  grep -qxF 'export HF_HOME="$HOME/.cache/huggingface"' "$HOME/.config/my-init-pipeline/env.sh"

  printf '%s/\n' "$T/picked" | hf run
  [ -d "$T/picked" ]
  grep -qxF "export HF_HOME=\"$T/picked\"" "$HOME/.config/my-init-pipeline/env.sh"
  printf '\n' | hf run
  [ "$(hf_exports)" -eq 1 ]
  grep -qxF "export HF_HOME=\"$T/picked\"" "$HOME/.config/my-init-pipeline/env.sh"
  printf '~/hfx\n' | hf run
  grep -qxF 'export HF_HOME="$HOME/hfx"' "$HOME/.config/my-init-pipeline/env.sh"
  [ -d "$HOME/hfx" ]
  run bash -c "printf 'rel/hf\n' | MIP_USER_CONFIG='$T/config.sh' bash '$ROOT/lib/step.sh' '$ROOT/actions/hf-home.sh' run"
  [ "$status" -ne 0 ]
  [[ "$output" == *"absolute path"* ]]
  hf check
}

@test "hf-home: first run moves the default cache into the chosen path and removes the old dir" {
  mkdir -p "$HOME/.cache/huggingface/hub/models--x"; touch "$HOME/.cache/huggingface/token" "$HOME/.cache/huggingface/hub/models--x/blob"
  HF_HOME_DIR="$T/hf" action hf-home run </dev/null
  [ -f "$T/hf/token" ] && [ -f "$T/hf/hub/models--x/blob" ]
  [ -L "$HOME/.cache/huggingface" ] && [ "$(readlink "$HOME/.cache/huggingface")" = "$T/hf" ]
  [ -f "$HOME/.cache/huggingface/token" ]
}

@test "hf-home: the default-location symlink follows a re-point, is restored by the Check, and gives way to a real dir" {
  HF_HOME_DIR="$T/a" action hf-home run </dev/null
  [ "$(readlink "$HOME/.cache/huggingface")" = "$T/a" ]
  touch "$T/a/token"
  HF_HOME_DIR="$T/b" action hf-home run </dev/null
  [ "$(readlink "$HOME/.cache/huggingface")" = "$T/b" ] && [ -f "$T/b/token" ] && [ ! -e "$T/a" ]

  rm "$HOME/.cache/huggingface"
  run env HF_HOME_DIR="$T/b" bash "$ROOT/lib/step.sh" "$ROOT/actions/hf-home.sh" check
  [ "$status" -eq 1 ]
  HF_HOME_DIR="$T/b" action hf-home run </dev/null
  [ "$(readlink "$HOME/.cache/huggingface")" = "$T/b" ]
  HF_HOME_DIR="$T/b" action hf-home check

  # Back to the default: the symlink becomes a real directory holding the data.
  HF_HOME_DIR="$HOME/.cache/huggingface" action hf-home run </dev/null
  [ -d "$HOME/.cache/huggingface" ] && [ ! -L "$HOME/.cache/huggingface" ]
  [ -f "$HOME/.cache/huggingface/token" ] && [ ! -e "$T/b" ]
  HF_HOME_DIR="$HOME/.cache/huggingface" action hf-home check
  grep -qxF 'export HF_HOME="$HOME/.cache/huggingface"' "$HOME/.config/my-init-pipeline/env.sh"
}

@test "hf-home: re-pointing merges into an existing tree; a file present in both is kept and left behind" {
  HF_HOME_DIR="$T/a" action hf-home run </dev/null
  mkdir -p "$T/a/hub" "$T/b/hub"
  printf old >"$T/a/token"; printf new >"$T/b/token"
  touch "$T/a/hub/from-a" "$T/b/hub/from-b" "$T/a/.hidden"
  run env HF_HOME_DIR="$T/b" bash "$ROOT/lib/step.sh" "$ROOT/actions/hf-home.sh" run </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"kept $T/b/token"* ]]
  [ "$(cat "$T/b/token")" = new ] && [ "$(cat "$T/a/token")" = old ]
  [ -f "$T/b/hub/from-a" ] && [ -f "$T/b/hub/from-b" ] && [ -f "$T/b/.hidden" ]
  [ ! -e "$T/a/hub" ] && [ ! -e "$T/a/.hidden" ]
  grep -qxF "export HF_HOME=\"$T/b\"" "$HOME/.config/my-init-pipeline/env.sh"
  HF_HOME_DIR="$T/b" action hf-home check
}

@test "hf-home: a path inside (or containing) a non-empty HF_HOME is refused before anything moves" {
  HF_HOME_DIR="$T/a" action hf-home run </dev/null
  touch "$T/a/token"
  run env HF_HOME_DIR="$T/a/sub" bash "$ROOT/lib/step.sh" "$ROOT/actions/hf-home.sh" run </dev/null
  [ "$status" -ne 0 ] && [[ "$output" == *"inside the current HF_HOME"* ]]
  run env HF_HOME_DIR="$T" bash "$ROOT/lib/step.sh" "$ROOT/actions/hf-home.sh" run </dev/null
  [ "$status" -ne 0 ] && [[ "$output" == *"contains the current HF_HOME"* ]]
  [ -f "$T/a/token" ] && [ ! -e "$T/a/sub" ]
  HF_HOME_DIR="$T/a" action hf-home check
  # Same path again (Enter at the prompt): nothing moves, nothing is removed.
  printf '\n' | MIP_USER_CONFIG=<(echo 'HF_HOME_DIR=') bash "$ROOT/lib/step.sh" "$ROOT/actions/hf-home.sh" run
  [ -f "$T/a/token" ]
}

@test "hf-home: an unwritable target fails before the export changes" {
  HF_HOME_DIR="$T/a" action hf-home run </dev/null
  mkdir -p "$T/ro"; chmod 555 "$T/ro"
  run env HF_HOME_DIR="$T/ro/hf" bash "$ROOT/lib/step.sh" "$ROOT/actions/hf-home.sh" run </dev/null
  chmod 755 "$T/ro"
  [ "$status" -ne 0 ] && [[ "$output" == *"cannot create or write"* ]]
  HF_HOME_DIR="$T/a" action hf-home check
}

@test "hf-home: a conflicting file left in ~/.cache/huggingface blocks the symlink and keeps the Check failing" {
  mkdir -p "$HOME/.cache/huggingface" "$T/hf"; printf old >"$HOME/.cache/huggingface/token"; printf new >"$T/hf/token"
  run env HF_HOME_DIR="$T/hf" bash "$ROOT/lib/step.sh" "$ROOT/actions/hf-home.sh" run </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"still has files"* ]]
  [ ! -L "$HOME/.cache/huggingface" ] && [ "$(cat "$HOME/.cache/huggingface/token")" = old ]
  run env HF_HOME_DIR="$T/hf" bash "$ROOT/lib/step.sh" "$ROOT/actions/hf-home.sh" check
  [ "$status" -eq 1 ]
  rm "$HOME/.cache/huggingface/token"
  HF_HOME_DIR="$T/hf" action hf-home run </dev/null
  [ "$(readlink "$HOME/.cache/huggingface")" = "$T/hf" ]
  HF_HOME_DIR="$T/hf" action hf-home check
}

# fake_uv — a uv on PATH whose `python install V...` marks each V installed under
# $T/py and whose `python find --system --python-preference only-managed V` succeeds
# only for those. Like the real uv, it rejects --managed-python while
# UV_PYTHON_PREFERENCE is set.
fake_uv() {
  mkdir -p "$T/bin" "$T/py"
  cat >"$T/bin/uv" <<'SH'
#!/bin/bash
echo "uv $*" >>"$T/events"
if [ -n "$UV_PYTHON_PREFERENCE" ] && [[ " $* " == *" --managed-python "* ]]; then exit 2; fi
case "$1 $2" in
  "python install") shift 2; for v in "$@"; do touch "$T/py/$v"; done ;;
  "python find") [ "$3 $4 $5" = "--system --python-preference only-managed" ] && [ -f "$T/py/$6" ] && echo "$T/py/$6" ;;
  *) exit 1 ;;
esac
SH
  chmod +x "$T/bin/uv"
}

@test "python: installs every configured version and exports UV_PYTHON_PREFERENCE=only-managed" {
  fake_uv
  run env PATH="$T/bin:$PATH" bash "$ROOT/lib/step.sh" "$ROOT/actions/python-install.sh" check
  [ "$status" -eq 1 ]
  PATH="$T/bin:$PATH" action python-install run
  grep -qxF 'uv python install 3.10 3.12' "$T/events"
  grep -qxF 'export UV_PYTHON_PREFERENCE="only-managed"' "$HOME/.config/my-init-pipeline/env.sh"
  PATH="$T/bin:$PATH" action python-install check
  run bash -c ". $ENV_SH; echo \"\$UV_PYTHON_PREFERENCE\""
  [ "$output" = only-managed ]
}

@test "python: the Check fails while a version or the export is missing; an empty setting fails loudly" {
  fake_uv
  touch "$T/py/3.10" "$T/py/3.12"
  run env PATH="$T/bin:$PATH" bash "$ROOT/lib/step.sh" "$ROOT/actions/python-install.sh" check
  [ "$status" -eq 1 ]                        # installed, but uv would still pick a system Python
  PATH="$T/bin:$PATH" action python-install run
  PATH="$T/bin:$PATH" action python-install check
  run env PATH="$T/bin:$PATH" MANAGED_PYTHON_VERSIONS="3.12 3.13" bash "$ROOT/lib/step.sh" "$ROOT/actions/python-install.sh" check
  [ "$status" -eq 1 ]
  PATH="$T/bin:$PATH" MANAGED_PYTHON_VERSIONS="3.12 3.13" action python-install run
  grep -qxF 'uv python install 3.12 3.13' "$T/events"
  PATH="$T/bin:$PATH" MANAGED_PYTHON_VERSIONS="3.12 3.13" action python-install check
  [ "$(grep -c '^export UV_PYTHON_PREFERENCE=' "$HOME/.config/my-init-pipeline/env.sh")" -eq 1 ]

  printf 'MANAGED_PYTHON_VERSIONS=\n' >"$T/config.sh"
  run env PATH="$T/bin:$PATH" MIP_USER_CONFIG="$T/config.sh" bash "$ROOT/lib/step.sh" "$ROOT/actions/python-install.sh" run
  [ "$status" -ne 0 ]
  [[ "$output" == *"MANAGED_PYTHON_VERSIONS"* ]]
}
