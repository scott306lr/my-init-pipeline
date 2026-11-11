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
#          Upgrade fast-forwards the clone to its upstream (git pull --ff-only),
#          then re-runs install.sh -y, which also repairs plugin caches. A clone
#          with uncommitted changes or local commits is not pulled: publishing
#          and merging stay with /sync-claude (the setup repo's sync.sh), and a
#          Note says so.

WARNINGS_FILE="$MIP_STATE_DIR/claude-config.warnings"
PULL_FILE="$MIP_STATE_DIR/claude-config.pull"

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

upgrade() {
  pull_config
  install_config
}

# pull_config — fast-forward the clone, unless it holds work of yours; records
# why it did not in PULL_FILE for the Note.
pull_config() {
  local dir="$CLAUDE_SETUP_DIR"
  mkdir -p "$MIP_STATE_DIR"
  : >"$PULL_FILE"
  if [ -n "$(git -C "$dir" status --porcelain)" ]; then
    echo "$dir has uncommitted changes, so it was not pulled; publish them with /sync-claude" >"$PULL_FILE"
  elif ! git -C "$dir" pull --ff-only --quiet; then
    echo "$dir could not be fast-forwarded (local commits?), so it was not pulled; run /sync-claude" >"$PULL_FILE"
  else
    info "$dir at $(git -C "$dir" log -1 --format='%h %s')"
  fi
}

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
  if [ "$1" = upgraded ] && [ -s "$PULL_FILE" ]; then cat "$PULL_FILE"; fi
  [ -s "$WARNINGS_FILE" ] || return 0
  echo "install.sh reported problems (see this Step's log):"
  sed 's/^/  /' "$WARNINGS_FILE"
}
