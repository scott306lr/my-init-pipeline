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

# A local release tarball with the binary nested like dust's/delta's layouts.
make_release() {
  mkdir -p "$T/rel/tool-v1-x86_64/sub"
  printf '#!/bin/sh\necho tool v1\n' >"$T/rel/tool-v1-x86_64/sub/tool"
  chmod +x "$T/rel/tool-v1-x86_64/sub/tool"
  tar -czf "$T/tool.tar.gz" -C "$T/rel" tool-v1-x86_64
  printf '%s  tool.tar.gz\n%s  other.tar.gz\n' "$(sha256sum "$T/tool.tar.gz" | cut -d' ' -f1)" deadbeef >"$T/checksums.txt"
}

@test "release_sha256 picks the named file from a checksums list" {
  make_release
  [ "$(release_sha256 "file://$T/checksums.txt" tool.tar.gz)" = "$(sha256sum "$T/tool.tar.gz" | cut -d' ' -f1)" ]
  [ -z "$(release_sha256 "file://$T/checksums.txt" missing.tar.gz)" ]
}

@test "install_release_binary installs a nested binary when the checksum matches" {
  make_release
  install_release_binary "file://$T/tool.tar.gz" tool "$(release_sha256 "file://$T/checksums.txt" tool.tar.gz)"
  [ "$("$HOME/.local/bin/tool")" = "tool v1" ]
}

@test "install_release_binary refuses a tampered archive and installs nothing" {
  make_release
  run install_release_binary "file://$T/tool.tar.gz" tool 0000000000000000000000000000000000000000000000000000000000000000
  [ "$status" -ne 0 ]
  [ ! -e "$HOME/.local/bin/tool" ]
}

@test "install_release_binary fails when the archive lacks the binary" {
  make_release
  run install_release_binary "file://$T/tool.tar.gz" nothere
  [ "$status" -ne 0 ]
}
