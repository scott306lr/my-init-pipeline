# summary: Install OpenAI Codex CLI with the official standalone installer (no Node)
# check:   codex is on PATH
# notes:   https://chatgpt.com/codex/install.sh into ~/.local/bin. CODEX_NON_INTERACTIVE=1
#          is required: the installer otherwise prompts via /dev/tty even when run
#          in the background. It leaves rc files alone when ~/.local/bin is on PATH.
#          Upgrade re-runs the installer.

check() { have codex; }

run() {
  run_installer https://chatgpt.com/codex/install.sh CODEX_NON_INTERACTIVE=1
  codex --version
}

upgrade() { run; }

note() { echo "Log in to Codex: run 'codex login'."; }
