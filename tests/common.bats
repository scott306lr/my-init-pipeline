#!/usr/bin/env bats
# lib/common.sh: the managed env file and the ~/.bashrc marker block.

load helpers

setup() {
  setup_pipeline
  . "$ROOT/lib/common.sh"
}

@test "add_path is idempotent and keeps the path unexpanded" {
  add_path '$HOME/.local/bin'
  add_path '$HOME/.local/bin'
  [ "$(grep -c 'local/bin' "$MIP_ENV_FILE")" -eq 1 ]
  grep -qF '"$HOME/.local/bin:$PATH"' "$MIP_ENV_FILE"
  env_has_path '$HOME/.local/bin'
  ! env_has_path '$HOME/other'
}

@test "sourcing env.sh repeatedly never duplicates a PATH entry" {
  add_path '$HOME/.local/bin'
  run bash -c ". '$MIP_ENV_FILE'; . '$MIP_ENV_FILE'; echo \"\$PATH\" | tr : '\n' | grep -c '^$HOME/.local/bin\$'"
  [ "$output" -eq 1 ]
}

@test "hook_bashrc appends exactly one marker block and preserves existing content" {
  printf 'existing line\n' >"$HOME/.bashrc"
  hook_bashrc; hook_bashrc
  [ "$(grep -c '>>> my-init-pipeline >>>' "$HOME/.bashrc")" -eq 1 ]
  [ "$(head -n1 "$HOME/.bashrc")" = "existing line" ]
  grep -qF '$HOME/.config/my-init-pipeline/env.sh' "$HOME/.bashrc"
}

@test "a fresh bash login picks up the PATH through ~/.bashrc" {
  add_path '$HOME/.local/bin'
  hook_bashrc
  run env -i HOME="$HOME" PATH=/usr/bin:/bin bash -c ". \"\$HOME/.bashrc\"; echo \"\$PATH\""
  [[ "$output" == "$HOME/.local/bin:"* ]]
}

@test "add_shell_init is idempotent and only runs in interactive shells" {
  add_shell_init 'export MIP_HOOKED=1'
  add_shell_init 'export MIP_HOOKED=1'
  [ "$(grep -c MIP_HOOKED "$MIP_ENV_FILE")" -eq 1 ]
  env_has_shell_init 'export MIP_HOOKED=1'
  run bash -c ". '$MIP_ENV_FILE'; echo \"[\${MIP_HOOKED:-}]\""
  [ "$output" = "[]" ]
  run bash -ic ". '$MIP_ENV_FILE'; echo \"[\${MIP_HOOKED:-}]\"" </dev/null
  [[ "$output" == *"[1]"* ]]
}
