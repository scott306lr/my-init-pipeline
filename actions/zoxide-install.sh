# summary: Install zoxide (smarter cd: `z <partial dir>`) and hook it into interactive bash
# check:   zoxide is on PATH and its `zoxide init bash` line is in the managed env file
# notes:   Official installer into ~/.local/bin with `--sudo false`: the installer
#          otherwise falls back to sudo when a copy fails; this Step must fail
#          instead. The init line goes into ~/.config/my-init-pipeline/env.sh via
#          add_shell_init (interactive shells only), not into ~/.bashrc.
#          Upgrade re-runs the installer, which always fetches the latest release.

ZOXIDE_INIT='command -v zoxide >/dev/null && eval "$(zoxide init bash)"'

check() { have zoxide && env_has_shell_init "$ZOXIDE_INIT"; }

run() {
  have zoxide || install_zoxide
  add_shell_init "$ZOXIDE_INIT"
}

upgrade() { install_zoxide; }

install_zoxide() {
  local tmp
  tmp="$(mktemp)"
  fetch https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh "$tmp"
  sh "$tmp" --bin-dir "$HOME/.local/bin" --man-dir "$HOME/.local/share/man" --sudo false </dev/null
  rm -f "$tmp"
  zoxide --version
}

note() { echo "zoxide: in a new shell, 'z <part of a dir>' jumps there; 'zi' picks interactively (needs fzf)."; }
