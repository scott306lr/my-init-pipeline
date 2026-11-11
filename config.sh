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

# Identity for git commits, written to ~/.gitconfig by the git-identity Step when
# user.name / user.email are unset there. Not the GIT_AUTHOR_* variables git reads.
GIT_USER_NAME="${GIT_USER_NAME:-scott306lr}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-scott306lr@gmail.com}"

# Where Hugging Face keeps model and dataset downloads (the HF_HUB_CACHE variable),
# e.g. /data/hf/hub for a big disk, or a directory shared between users (see
# HF_HUB_CACHE_SHARED). The token stays in ~/.cache/huggingface.
# Empty: the hf-cache Step asks on the terminal instead (and is deferred in a
# non-interactive Run).
HF_HUB_CACHE_DIR="${HF_HUB_CACHE_DIR:-}"
# Share HF_HUB_CACHE_DIR with every user of the server (yes/no) when it lies
# outside your home. Empty: the hf-cache Step asks.
HF_HUB_CACHE_SHARED="${HF_HUB_CACHE_SHARED:-}"

# Python versions the python Step installs as uv-managed interpreters (space-separated).
# These ship their own C headers, unlike a system Python without its -dev package.
MANAGED_PYTHON_VERSIONS="${MANAGED_PYTHON_VERSIONS:-3.10 3.12}"
