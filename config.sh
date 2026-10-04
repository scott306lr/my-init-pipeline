# User settings read by Actions. Plain shell assignments; keep secrets out of here.
# Each can be overridden from the environment, e.g. for a container test:
#   CLAUDE_SETUP_PROTOCOL=https CLAUDE_SETUP_REF=my-branch ./init.sh run

# Private repo created from the my-portable-claude template, as owner/repo on GitHub.
CLAUDE_SETUP_REPO="${CLAUDE_SETUP_REPO:-scott306lr/my-claude-setup}"
CLAUDE_SETUP_DIR="${CLAUDE_SETUP_DIR:-$HOME/my-claude-setup}"
# How to clone it: https (works anywhere gh is logged in) or ssh (needs a key on GitHub).
CLAUDE_SETUP_PROTOCOL="${CLAUDE_SETUP_PROTOCOL:-https}"
# Branch to clone; empty means the repo's default branch. Only used for a fresh clone.
CLAUDE_SETUP_REF="${CLAUDE_SETUP_REF:-}"
