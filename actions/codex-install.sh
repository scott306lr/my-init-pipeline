# summary: Install OpenAI Codex CLI with the official standalone installer (no Node)
# check:   codex is on PATH and its config directory ($CODEX_HOME, default ~/.codex) exists
# notes:   https://chatgpt.com/codex/install.sh into ~/.local/bin. CODEX_NON_INTERACTIVE=1
#          is required: the installer otherwise prompts via /dev/tty even when run
#          in the background. It leaves rc files alone when ~/.local/bin is on PATH.
#          The installer does not create codex's config directory and codex makes
#          it only on first use (`codex login`), but Steps that configure codex
#          (herdr's integration) need it now, so this Step creates it, private
#          (700) since codex keeps its credentials there. Upgrade re-runs the
#          installer.

check() { have codex && [ -d "$(codex_home)" ]; }

run() {
  have codex || install_codex
  codex --version
  local home
  home="$(codex_home)"
  if [ ! -d "$home" ]; then
    mkdir -p "$home"
    chmod 700 "$home"
    info "created $home"
  fi
}

upgrade() { install_codex; }

install_codex() { run_installer https://chatgpt.com/codex/install.sh CODEX_NON_INTERACTIVE=1; }

# codex_home — codex's config directory: CODEX_HOME, else ~/.codex (codex-rs
# find_codex_home).
codex_home() { printf '%s\n' "${CODEX_HOME:-$HOME/.codex}"; }

note() { [ "$1" = upgraded ] || echo "Log in to Codex: run 'codex login'."; }
