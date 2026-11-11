#!/usr/bin/env bats
# Pure-logic parts of real Actions (no network): herdr hook rewrite, clone URLs.

load helpers

setup() {
  setup_pipeline
  unset HF_HUB_CACHE HF_DATASETS_CACHE HF_HOME   # the developer's own Hugging Face settings
  export HF_CACHE_SUGGESTED="$T/suggested"   # never the real /shared
  export MIP_USER_CONFIG="$ROOT/config.sh"
  mkdir -p "$HOME/.claude" "$T/repo"
  # settings.json is a symlink into the setup repo, as claude-config leaves it.
  ln -s "$T/repo/settings.json" "$HOME/.claude/settings.json"
}

action() { bash "$ROOT/lib/step.sh" "$ROOT/actions/$1.sh" "${@:2}"; }

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

# setup_clone — an origin and a clone of a claude setup repo whose install.sh
# only records that it ran.
setup_clone() {
  git -C "$T" init -q -b main setup-origin
  printf '#!/bin/sh\necho installed >>"%s/installs"\n' "$T" >"$T/setup-origin/install.sh"
  chmod +x "$T/setup-origin/install.sh"
  gitc() { git -c user.name=t -c user.email=t@t "$@"; }
  gitc -C "$T/setup-origin" add -A && gitc -C "$T/setup-origin" commit -qm one
  git clone -q "$T/setup-origin" "$T/setup"
  echo new >"$T/setup-origin/cfg" && gitc -C "$T/setup-origin" add cfg && gitc -C "$T/setup-origin" commit -qm two
  export CLAUDE_SETUP_DIR="$T/setup"
}

@test "claude-config: upgrade fast-forwards the clone, then re-runs install.sh" {
  setup_clone
  action claude-config upgrade
  [ "$(cat "$T/setup/cfg")" = new ] && [ "$(cat "$T/installs")" = installed ]
  run action claude-config note upgraded
  [ -z "$output" ]
}

@test "claude-config: upgrade leaves a clone with your work alone and says so in the Note" {
  setup_clone
  echo mine >"$T/setup/local-edit"
  action claude-config upgrade
  [ ! -e "$T/setup/cfg" ] && [ "$(cat "$T/installs")" = installed ]
  run action claude-config note upgraded
  [[ "$output" == *"uncommitted changes"*"/sync-claude"* ]]
  run action claude-config note ran                    # a first install says nothing about pulling
  [[ "$output" != *"sync-claude"* ]]

  rm "$T/setup/local-edit"
  echo other >"$T/setup/cfg"
  git -C "$T/setup" add cfg && git -C "$T/setup" -c user.name=t -c user.email=t@t commit -qm diverge
  action claude-config upgrade
  [ "$(cat "$T/setup/cfg")" = other ]
  run action claude-config note upgraded
  [[ "$output" == *"could not be fast-forwarded"* ]]
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
envf() { printf '%s\n' "$HOME/.config/my-init-pipeline/env.sh"; }
hfc() { bash "$ROOT/lib/step.sh" "$ROOT/actions/hf-cache.sh" "$1"; }

# exports ROOT — env.sh points HF_HUB_CACHE and HF_DATASETS_CACHE into ROOT (as written there).
exports() {
  grep -qxF "export HF_HUB_CACHE=\"$1/hub\"" "$(envf)" && grep -qxF "export HF_DATASETS_CACHE=\"$1/datasets\"" "$(envf)"
}

@test "hf-cache: HF_CACHE_DIR set — no prompt; exports hub/ and datasets/ in it; a changed setting is re-pointed" {
  run action hf-cache check
  [ "$status" -eq 1 ]
  HF_CACHE_DIR="$HOME/hf" action hf-cache run </dev/null
  [ -d "$HOME/hf/hub" ] && [ -d "$HOME/hf/datasets" ]
  exports '$HOME/hf'
  ! grep -q '^export HF_HOME=' "$(envf)"
  HF_CACHE_DIR="$HOME/hf" action hf-cache check
  action hf-cache check                      # unset setting: the recorded one is fine
  run bash -c ". $ENV_SH; echo \"\$HF_HUB_CACHE \$HF_DATASETS_CACHE\""
  [ "$output" = "$HOME/hf/hub $HOME/hf/datasets" ]

  run env HF_CACHE_DIR="$T/srv" HF_CACHE_SHARED=no bash "$ROOT/lib/step.sh" "$ROOT/actions/hf-cache.sh" check
  [ "$status" -eq 1 ]
  HF_CACHE_DIR="$T/srv" HF_CACHE_SHARED=no action hf-cache run </dev/null
  [ "$(grep -c '^export HF_HUB_CACHE=' "$(envf)")" -eq 1 ] && [ "$(grep -c '^export HF_DATASETS_CACHE=' "$(envf)")" -eq 1 ]
  exports "$T/srv"
  HF_CACHE_DIR="$T/srv" action hf-cache check
}

@test "hf-cache: HF_CACHE_DIR empty — prompts; Enter keeps the recorded folder; ~ expands; relative is refused" {
  printf 'HF_CACHE_DIR=\nHF_CACHE_SHARED=no\n' >"$T/config.sh"
  export MIP_USER_CONFIG="$T/config.sh"
  run hfc check
  [ "$status" -eq 1 ]                        # not na: a human can answer it
  run hfc run </dev/null                     # no terminal and nothing recorded: the suggestion applies
  [ "$status" -eq 0 ]
  exports "$T/suggested"
  printf '%s/\n' "$T/picked" | hfc run
  exports "$T/picked"
  printf '\n' | hfc run
  exports "$T/picked"
  printf '~/hfx\n' | hfc run
  exports '$HOME/hfx'
  run bash -c "printf 'rel/hf\n' | bash '$ROOT/lib/step.sh' '$ROOT/actions/hf-cache.sh' run"
  [ "$status" -ne 0 ]
  [[ "$output" == *"absolute path"* ]]
  hfc check
}

@test "hf-cache: needs no human once its settings answer every question; the prompt defaults to a system-wide cache folder" {
  run env HF_CACHE_DIR=/x HF_CACHE_SHARED=no bash "$ROOT/lib/step.sh" "$ROOT/actions/hf-cache.sh" interactive
  [ "$status" -eq 1 ]
  printf 'HF_CACHE_DIR=\nHF_CACHE_SHARED=no\n' >"$T/config.sh"
  export MIP_USER_CONFIG="$T/config.sh"
  hfc interactive
  HF_HUB_CACHE="$T/sys/hub" hfc run </dev/null
  exports "$T/sys"
}

@test "hf-cache: an earlier HF_HUB_CACHE=<folder>/hub becomes the folder; nothing in it moves" {
  mkdir -p "$T/old/hub/models--x" "$HOME/.config/my-init-pipeline"
  printf 'export HF_HUB_CACHE="%s/hub"\n' "$T/old" >"$(envf)"
  printf 'HF_CACHE_DIR=\nHF_CACHE_SHARED=no\n' >"$T/config.sh"
  run hfc check
  [ "$status" -eq 1 ]                        # no HF_DATASETS_CACHE yet
  MIP_USER_CONFIG="$T/config.sh" bash "$ROOT/lib/step.sh" "$ROOT/actions/hf-cache.sh" run </dev/null
  exports "$T/old"
  [ -d "$T/old/hub/models--x" ] && [ -d "$T/old/datasets" ]
}

@test "hf-cache: re-pointing moves your hub and datasets downloads; snapshot links still resolve" {
  local h="$HOME/.cache/huggingface"
  mkdir -p "$h/hub/models--x/snapshots/abc" "$h/hub/blobs/12" "$h/datasets/ds___y/0.0.0"
  echo weights >"$h/hub/blobs/12/1234"
  ln -s ../../../blobs/12/1234 "$h/hub/models--x/snapshots/abc/model.safetensors"
  echo arrow >"$h/datasets/ds___y/0.0.0/data.arrow"
  run env HF_CACHE_DIR="$T/new" HF_CACHE_SHARED=no bash "$ROOT/lib/step.sh" "$ROOT/actions/hf-cache.sh" run </dev/null
  [ "$status" -eq 0 ] && [[ "$output" == *"moving $h/hub into $T/new/hub"* ]]
  [ "$(cat "$T/new/hub/models--x/snapshots/abc/model.safetensors")" = weights ]
  [ "$(cat "$T/new/datasets/ds___y/0.0.0/data.arrow")" = arrow ]
  [ ! -e "$h/hub" ] && [ ! -e "$h/datasets" ]
  exports "$T/new"
}

@test "hf-cache: moving merges; an entry the new folder already has is kept there and left behind" {
  mkdir -p "$T/a/hub/models--x/refs" "$T/b/hub/models--x/refs" "$T/a/datasets" "$T/b/datasets" "$HOME/.config/my-init-pipeline"
  printf 'export HF_HUB_CACHE="%s/hub"\nexport HF_DATASETS_CACHE="%s/datasets"\n' "$T/a" "$T/a" >"$(envf)"
  echo old >"$T/a/hub/models--x/refs/main"; echo new >"$T/b/hub/models--x/refs/main"
  touch "$T/a/hub/models--x/refs/pr-1" "$T/b/hub/models--x/refs/pr-2"
  run env HF_CACHE_DIR="$T/b" HF_CACHE_SHARED=no bash "$ROOT/lib/step.sh" "$ROOT/actions/hf-cache.sh" run </dev/null
  [ "$status" -eq 0 ] && [[ "$output" == *"1 entries were already in $T/b/hub"* ]]
  [ "$(cat "$T/b/hub/models--x/refs/main")" = new ] && [ "$(cat "$T/a/hub/models--x/refs/main")" = old ]
  [ -e "$T/b/hub/models--x/refs/pr-1" ] && [ -e "$T/b/hub/models--x/refs/pr-2" ]
  exports "$T/b"
}

@test "hf-cache: an unwritable target fails before the exports change" {
  HF_CACHE_DIR="$T/a" HF_CACHE_SHARED=no action hf-cache run </dev/null
  mkdir -p "$T/ro"; chmod 555 "$T/ro"
  run env HF_CACHE_DIR="$T/ro/hf" HF_CACHE_SHARED=no bash "$ROOT/lib/step.sh" "$ROOT/actions/hf-cache.sh" run </dev/null
  chmod 755 "$T/ro"
  [ "$status" -ne 0 ] && [[ "$output" == *"cannot create or write"* ]]
  exports "$T/a"
}

@test "hf-cache: undoes a relocated HF_HOME — token back in a private ~/.cache/huggingface, caches left, export dropped" {
  # What the former hf-home Step left: a shared HF_HOME, exported and symlinked.
  mkdir -p "$T/shared/hub/models--x" "$T/shared/datasets/d" "$T/shared/xet" "$HOME/.cache" "$HOME/.config/my-init-pipeline"
  printf tok >"$T/shared/token"; touch "$T/shared/stored_tokens"
  ln -s "$T/shared" "$HOME/.cache/huggingface"
  printf 'export HF_HOME="%s"\n' "$T/shared" >"$(envf)"
  run env HF_CACHE_DIR="$T/shared" HF_CACHE_SHARED=no bash "$ROOT/lib/step.sh" "$ROOT/actions/hf-cache.sh" check
  [ "$status" -eq 1 ]
  HF_CACHE_DIR="$T/shared" HF_CACHE_SHARED=no action hf-cache run </dev/null
  [ -d "$HOME/.cache/huggingface" ] && [ ! -L "$HOME/.cache/huggingface" ]
  [ "$(stat -c %a "$HOME/.cache/huggingface")" = 700 ]
  [ "$(cat "$HOME/.cache/huggingface/token")" = tok ] && [ -f "$HOME/.cache/huggingface/stored_tokens" ] && [ -d "$HOME/.cache/huggingface/xet" ]
  [ ! -e "$T/shared/token" ] && [ -d "$T/shared/hub/models--x" ] && [ -d "$T/shared/datasets/d" ]
  ! grep -q '^export HF_HOME=' "$(envf)"
  HF_CACHE_DIR="$T/shared" action hf-cache check
}

@test "hf-cache: the prompt defaults to the relocated HF_HOME; a name already at home is left in place" {
  mkdir -p "$T/old/hub" "$HOME/.cache/huggingface" "$HOME/.config/my-init-pipeline"
  printf old >"$T/old/token"; printf new >"$HOME/.cache/huggingface/token"
  printf 'export HF_HOME="%s"\n' "$T/old" >"$(envf)"
  printf 'HF_CACHE_DIR=\nHF_CACHE_SHARED=no\n' >"$T/config.sh"
  run env MIP_USER_CONFIG="$T/config.sh" bash "$ROOT/lib/step.sh" "$ROOT/actions/hf-cache.sh" run </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"left $T/old/token"* ]]
  [ "$(cat "$HOME/.cache/huggingface/token")" = new ] && [ "$(cat "$T/old/token")" = old ]
  exports "$T/old"
  ! grep -q '^export HF_HOME=' "$(envf)"
}

@test "hf-cache: the suggestion is HF_CACHE_SUGGESTED when you can create it, else ~/.cache/huggingface" {
  printf 'HF_CACHE_DIR=\nHF_CACHE_SHARED=no\n' >"$T/config.sh"
  export MIP_USER_CONFIG="$T/config.sh"
  mkdir -p "$T/ro"; chmod 555 "$T/ro"
  HF_CACHE_SUGGESTED="$T/ro/shared" hfc run </dev/null     # not creatable: HF's default
  chmod 755 "$T/ro"
  exports '$HOME/.cache/huggingface'
  rm "$(envf)"
  hfc run </dev/null
  exports "$T/suggested"
  rm "$(envf)"
  run env HF_CACHE_SUGGESTED= bash "$ROOT/lib/step.sh" "$ROOT/actions/hf-cache.sh" run </dev/null
  [ "$status" -eq 0 ]                        # an empty setting falls back too
}

@test "hf-cache: Note tells a shell that still has HF_HOME to drop it" {
  run env HF_HOME=/x bash "$ROOT/lib/step.sh" "$ROOT/actions/hf-cache.sh" note
  [[ "$output" == *"unset HF_HOME"* ]]
  run env -u HF_HOME bash "$ROOT/lib/step.sh" "$ROOT/actions/hf-cache.sh" note
  [ -z "$output" ]
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

# fake_uv_bin — a uv on PATH that logs its arguments and UV_NO_MODIFY_PATH, and
# an installer (file:// URL) that writes a receipt, as the real one does.
fake_uv_bin() {
  mkdir -p "$T/bin"
  printf '#!/bin/sh\necho "uv $* nomod=$UV_NO_MODIFY_PATH" >>"%s/uv.calls"\n' "$T" >"$T/bin/uv"
  chmod +x "$T/bin/uv"
  printf '#!/bin/sh\necho "installer nomod=$UV_NO_MODIFY_PATH" >>"%s/uv.calls"\nmkdir -p "$HOME/.config/uv" && echo {} >"$HOME/.config/uv/uv-receipt.json"\n' "$T" >"$T/uv-install.sh"
  export PATH="$T/bin:$PATH" MIP_UV_INSTALLER_URL="file://$T/uv-install.sh"
}

@test "uv: upgrade self-updates a standalone install, without touching shell profiles" {
  fake_uv_bin
  mkdir -p "$HOME/.config/uv"; echo {} >"$HOME/.config/uv/uv-receipt.json"
  action uv-install upgrade
  grep -qx 'uv self update nomod=1' "$T/uv.calls"
  ! grep -q installer "$T/uv.calls"
}

@test "uv: upgrade reinstalls a uv with no install receipt, after which it self-updates" {
  fake_uv_bin
  action uv-install upgrade
  grep -qx 'installer nomod=1' "$T/uv.calls"
  ! grep -q 'self update' "$T/uv.calls"
  action uv-install upgrade
  grep -qx 'uv self update nomod=1' "$T/uv.calls"
}


# Sharing (no root needed: you own the folder).
share_cfg() { printf 'HF_CACHE_DIR=%s\nHF_CACHE_SHARED=%s\n' "$1" "$2" >"$T/config.sh"; export MIP_USER_CONFIG="$T/config.sh"; }
shared_dir() { getfacl -p "$1" | grep -qx 'other::rwx' && getfacl -p "$1" | grep -qx 'default:other::rwx'; }

@test "hf-cache: HF_CACHE_SHARED=yes shares a folder outside home (hub/ and datasets/) with everyone; the Check requires it" {
  command -v setfacl >/dev/null || skip "setfacl (acl) not installed"
  share_cfg "$T/srv" yes
  run hfc interactive
  [ "$status" -eq 1 ]                        # both answered: no human needed
  hfc run </dev/null
  shared_dir "$T/srv" && shared_dir "$T/srv/hub" && shared_dir "$T/srv/datasets"
  hfc check
  run hfc note                               # not exported system-wide here: say how
  [[ "$output" == *"./init.sh run hf-export"* ]]
  setfacl -b "$T/srv"; chmod 755 "$T/srv"
  run hfc check
  [ "$status" -eq 1 ]
}

@test "hf-cache: downloads moved into a shared folder become everyone's too; a shared old cache is left alone" {
  command -v setfacl >/dev/null || skip "setfacl (acl) not installed"
  mkdir -p "$HOME/.cache/huggingface/hub/models--x/refs"
  echo abc >"$HOME/.cache/huggingface/hub/models--x/refs/main"; chmod 600 "$HOME/.cache/huggingface/hub/models--x/refs/main"
  share_cfg "$T/srv" yes
  hfc run </dev/null
  shared_dir "$T/srv/hub/models--x/refs"
  getfacl -p "$T/srv/hub/models--x/refs/main" | grep -qx 'other::rw-'
  # Back to a private folder: the shared one keeps everything.
  share_cfg "$HOME/mine" no
  run hfc run </dev/null
  [[ "$output" == *"is shared with other users, so its downloads stay there"* ]]
  [ -e "$T/srv/hub/models--x/refs/main" ]
}

@test "hf-cache: asks whether to share only outside home and only if not shared; n keeps it private" {
  command -v setfacl >/dev/null || skip "setfacl (acl) not installed"
  share_cfg "$T/srv" ""
  hfc interactive                            # the question is open
  printf 'n\n' | hfc run
  ! shared_dir "$T/srv"
  hfc check                                  # unset setting: private is fine
  printf '\n' | hfc run                     # Enter: yes
  shared_dir "$T/srv"
  run hfc interactive                        # shared now: nothing to ask
  [ "$status" -eq 1 ]
  share_cfg "$HOME/hf" ""
  run hfc interactive                        # inside home: never asked
  [ "$status" -eq 1 ]
}

@test "hf-export: n/a only for a cache folder in your home; work to do before hf-cache ran, and until shared and exported" {
  run env HF_HUB_CACHE= bash "$ROOT/lib/step.sh" "$ROOT/actions/hf-export.sh" check
  [ "$status" -eq 1 ]                        # fresh server: offered, hf-cache will record the folder
  run env HF_HUB_CACHE="$HOME/hf/hub" HF_DATASETS_CACHE="$HOME/hf/datasets" bash "$ROOT/lib/step.sh" "$ROOT/actions/hf-export.sh" check
  [ "$status" -eq 2 ]
  mkdir -p "$T/priv/hub" "$T/priv/datasets"
  run env HF_HUB_CACHE="$T/priv/hub" HF_DATASETS_CACHE="$T/priv/datasets" bash "$ROOT/lib/step.sh" "$ROOT/actions/hf-export.sh" check
  [ "$status" -eq 1 ]                        # outside home, not shared: root shares and exports it
  run env HF_HUB_CACHE="$T/priv/hub" HF_DATASETS_CACHE= bash "$ROOT/lib/step.sh" "$ROOT/actions/hf-export.sh" run
  [ "$status" -ne 0 ] && [[ "$output" == *"run the hf-cache Step first"* ]]
}

@test "hf-export: a terminal only when sudo needs a password; without one it never lets sudo prompt" {
  mkdir -p "$T/bin"
  printf '#!/bin/sh\necho "$*" >>"%s/sudo.calls"\nexit "${SUDO_RC:-0}"\n' "$T" >"$T/bin/sudo"; chmod +x "$T/bin/sudo"
  export PATH="$T/bin:$PATH"
  run env SUDO_RC=0 bash "$ROOT/lib/step.sh" "$ROOT/actions/hf-export.sh" interactive
  [ "$status" -eq 1 ]
  SUDO_RC=1 bash "$ROOT/lib/step.sh" "$ROOT/actions/hf-export.sh" interactive
  : >"$T/sudo.calls"
  export HF_HUB_CACHE="$T/srv/hub" HF_DATASETS_CACHE="$T/srv/datasets"
  run env SUDO_RC=0 bash "$ROOT/lib/step.sh" "$ROOT/actions/hf-export.sh" run </dev/null
  [ "$status" -eq 0 ]
  grep -qxF -- "-n bash $ROOT/admin/share-hf-cache.sh $T/srv" "$T/sudo.calls"
  run env SUDO_RC=1 bash "$ROOT/lib/step.sh" "$ROOT/actions/hf-export.sh" run </dev/null
  [ "$status" -ne 0 ] && [[ "$output" == *"run it on a terminal: ./init.sh run hf-export"* ]]
}

@test "hf-export: on a terminal, run prints the sudo command, or what to ask an admin" {
  command -v script >/dev/null || skip "util-linux script not available"
  mkdir -p "$T/bin"
  printf '#!/bin/sh\necho "$*" >>"%s/sudo.calls"\nexit "${SUDO_RC:-0}"\n' "$T" >"$T/bin/sudo"; chmod +x "$T/bin/sudo"
  export PATH="$T/bin:$PATH"
  on_tty() { script -qec "env SUDO_RC=$1 HF_HUB_CACHE=$T/srv/hub HF_DATASETS_CACHE=$T/srv/datasets bash $ROOT/lib/step.sh $ROOT/actions/hf-export.sh run" /dev/null; }
  run on_tty 0
  [ "$status" -eq 0 ] && [[ "$output" == *"hf-export needs sudo: sudo bash $ROOT/admin/share-hf-cache.sh $T/srv"* ]]
  grep -qxF "bash $ROOT/admin/share-hf-cache.sh $T/srv" "$T/sudo.calls"
  run on_tty 1
  [ "$status" -ne 0 ] && [[ "$output" == *"ask an admin to run: curl"*"sudo bash -s -- $T/srv"* ]]
}

@test "codex: the Check needs codex's config directory; run creates it private without reinstalling" {
  mkdir -p "$T/bin"
  printf '#!/bin/sh\necho "codex-cli 9.9"\n' >"$T/bin/codex"; chmod +x "$T/bin/codex"
  export PATH="$T/bin:$PATH"
  run action codex-install check
  [ "$status" -eq 1 ]                        # on PATH, but no ~/.codex yet (herdr needs it)
  action codex-install run                   # codex is there: no installer download
  [ "$(stat -c %a "$HOME/.codex")" = 700 ]
  action codex-install check
  mkdir -p "$T/codex-home"
  run env CODEX_HOME="$T/codex-home" bash "$ROOT/lib/step.sh" "$ROOT/actions/codex-install.sh" check
  [ "$status" -eq 0 ]                        # CODEX_HOME is honoured
}

@test "hf-cache: downloads moved into a group-shared folder (setgid, group-writable, no ACL) get its group and group write" {
  mkdir -p "$T/grp/hub" "$T/grp/datasets" "$HOME/.cache/huggingface/datasets/ds___y" "$HOME/.cache/huggingface/hub/blobs/12"
  chmod 2775 "$T/grp" "$T/grp/hub" "$T/grp/datasets"
  echo a >"$HOME/.cache/huggingface/datasets/ds___y/f"; chmod 600 "$HOME/.cache/huggingface/datasets/ds___y/f"
  echo w >"$HOME/.cache/huggingface/hub/blobs/12/1234"; chmod 444 "$HOME/.cache/huggingface/hub/blobs/12/1234"
  HF_CACHE_DIR="$T/grp" HF_CACHE_SHARED=no action hf-cache run </dev/null
  [ "$(stat -c %a "$T/grp/datasets/ds___y/f")" = 660 ]
  [ -g "$T/grp/datasets/ds___y" ]
  [ "$(stat -c %a "$T/grp/hub/blobs/12/1234")" = 444 ]   # blob payloads stay read-only
}
