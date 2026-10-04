# summary: Install Claude Code with the official native installer (~/.local/bin/claude)
# check:   claude is on PATH
# notes:   https://claude.ai/install.sh — downloads, verifies sha256, links
#          ~/.local/bin/claude. Upgrade uses `claude update`.

check() { have claude; }

run() {
  local tmp
  tmp="$(mktemp)"
  fetch https://claude.ai/install.sh "$tmp"
  bash "$tmp" </dev/null
  rm -f "$tmp"
  claude --version
}

upgrade() { claude update; }

note() { echo "Log in to Claude Code: run 'claude' and use /login."; }
