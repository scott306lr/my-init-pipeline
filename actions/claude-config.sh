# summary: Clone the private claude setup repo and link it into ~/.claude (install.sh -y)
# check:   the repo is cloned and ~/.claude/settings.json links into it
# notes:   Follows the my-portable-claude README for every machine after the first:
#          clone $CLAUDE_SETUP_REPO to $CLAUDE_SETUP_DIR, then `./install.sh`.
#          CLAUDE_SETUP_PROTOCOL picks https or ssh; CLAUDE_SETUP_REF a branch.
#          An existing clone is never re-cloned or switched to another branch.
#          Uses -y (overwrite without asking; install.sh still keeps backups).
#          Runs `gh auth setup-git` first so plugin marketplaces in private repos
#          clone over HTTPS, and allows 5 min per marketplace clone (some are huge).
#          install.sh exits 0 even when a marketplace fails; those warnings come
#          back as a Note instead of failing the Step.
#          Settings live in config.sh.
#          Upgrade re-runs install.sh -y, which also repairs plugin caches; pulling
#          new config is sync-claude's job, not this Step's.

WARNINGS_FILE="$MIP_STATE_DIR/claude-config.warnings"

check() {
  [ -d "$CLAUDE_SETUP_DIR/.git" ] || return 1
  local target
  target="$(readlink -f "$HOME/.claude/settings.json" 2>/dev/null)" || return 1
  [[ "$target" == "$(cd "$CLAUDE_SETUP_DIR" && pwd -P)/"* ]]
}

run() {
  gh auth setup-git
  if [ ! -d "$CLAUDE_SETUP_DIR/.git" ]; then
    git clone ${CLAUDE_SETUP_REF:+--branch "$CLAUDE_SETUP_REF"} "$(clone_url)" "$CLAUDE_SETUP_DIR"
  fi
  install_config
}

upgrade() { install_config; }

clone_url() {
  case "$CLAUDE_SETUP_PROTOCOL" in
    https) echo "https://github.com/$CLAUDE_SETUP_REPO.git" ;;
    ssh) echo "git@github.com:$CLAUDE_SETUP_REPO.git" ;;
    *) die "CLAUDE_SETUP_PROTOCOL must be https or ssh, got '$CLAUDE_SETUP_PROTOCOL'" ;;
  esac
}

install_config() {
  local log
  log="$(mktemp)"
  (
    cd "$CLAUDE_SETUP_DIR" || exit
    CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS="${CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS:-300000}" ./install.sh -y </dev/null
  ) 2>&1 | tee "$log"
  local rc=${PIPESTATUS[0]}
  mkdir -p "$MIP_STATE_DIR"
  grep -F 'could NOT' "$log" | sed 's/^[^a-zA-Z]*//' >"$WARNINGS_FILE" || true
  rm -f "$log"
  return "$rc"
}

note() {
  [ -s "$WARNINGS_FILE" ] || return 0
  echo "install.sh reported problems (see this Step's log):"
  sed 's/^/  /' "$WARNINGS_FILE"
}
