# summary: Install herdr and its claude + codex integrations
# check:   herdr is on PATH, `herdr integration status` shows claude and codex
#          current, and settings.json has no machine-specific herdr hook
# notes:   https://herdr.dev/install.sh into ~/.local/bin. Must run after claude-config
#          and codex: `herdr integration install` needs ~/.claude and ~/.codex to exist.
#          The claude integration writes into ~/.claude/settings.json, a symlink into
#          the shared claude setup repo. herdr always adds a SessionStart hook with this
#          machine's absolute path (bash '/home/<user>/.claude/hooks/...' session); that
#          would leak one machine's path to every other, so this Step rewrites it to the
#          portable "$HOME/..." form. herdr's status reads only the hook script, so the
#          rewrite doesn't make it look outdated. The hook script itself (v9 → v10)
#          is a real fleet-wide update: sync it.

HERDR_AGENTS=(claude codex)
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

integrations_current() {
  local status a
  status="$(herdr integration status)" || return 1
  for a in "${HERDR_AGENTS[@]}"; do
    grep -q "^$a: " <<<"$status" || return 1
    grep -Eq "^$a: (not installed|outdated)" <<<"$status" && return 1
  done
  return 0
}

check() { have herdr && integrations_current && portable_hooks --check; }

run() {
  have herdr || run_installer https://herdr.dev/install.sh
  herdr --version
  install_integrations
}

install_integrations() {
  local a
  for a in "${HERDR_AGENTS[@]}"; do herdr integration install "$a" </dev/null; done
  portable_hooks
  herdr integration status | grep -E "^($(IFS='|'; echo "${HERDR_AGENTS[*]}")): "
}

upgrade() {
  herdr update </dev/null
  integrations_current || install_integrations
}

# portable_hooks [--check] — replace herdr's absolute-path SessionStart hook with
# the $HOME form (dropping it if that form is already there). --check only
# reports whether anything would change. Writes through the symlink, and only
# when something changes.
portable_hooks() {
  [ -f "$CLAUDE_SETTINGS" ] || return 0
  python3 - "$CLAUDE_SETTINGS" "$HOME" "${1:-}" <<'PY'
import json, sys

path, home, mode = sys.argv[1], sys.argv[2], sys.argv[3]
script = "/.claude/hooks/herdr-agent-state.sh"
absolute = f"bash '{home}{script}' session"
portable = f'bash "$HOME{script}" session'

with open(path) as f:
    raw = f.read()
settings = json.loads(raw)
groups = settings.get("hooks", {}).get("SessionStart", [])

def commands(group):
    return [h.get("command", "") for h in group.get("hooks", [])]

has_portable = any(c.startswith(portable) for g in groups for c in commands(g))
changed = False
kept = []
for group in groups:
    hooks = []
    for h in group.get("hooks", []):
        if h.get("command") == absolute:
            changed = True
            if has_portable:
                continue  # the shared file already runs the hook portably
            h["command"] = portable
            has_portable = True
        hooks.append(h)
    if hooks:
        group["hooks"] = hooks
        kept.append(group)

if mode == "--check":
    sys.exit(1 if changed else 0)
if changed:
    settings["hooks"]["SessionStart"] = kept
    with open(path, "w") as f:  # follows the symlink into the setup repo
        f.write(json.dumps(settings, indent=2, ensure_ascii=False) + "\n")
    print(f"rewrote herdr's machine-specific SessionStart hook in {path}")
PY
}
