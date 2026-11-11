# summary: Install uv (Python tool manager) into ~/.local/bin
# check:   uv is on PATH
# notes:   https://astral.sh/uv/install.sh with UV_NO_MODIFY_PATH=1 (path-env owns
#          PATH). Needed because servers often lack pip/ensurepip without root.
#          Upgrade follows uv's docs: `uv self update` works only for a uv the
#          standalone installer put there (it leaves a receipt in ~/.config/uv).
#          A uv without one (copied in, or from a package manager) is replaced
#          by a standalone install into ~/.local/bin, which path-env puts first,
#          so later upgrades self-update. UV_NO_MODIFY_PATH=1 keeps either from
#          editing shell profiles.

UV_INSTALLER_URL="${MIP_UV_INSTALLER_URL:-https://astral.sh/uv/install.sh}"   # override: tests
UV_RECEIPT="${XDG_CONFIG_HOME:-$HOME/.config}/uv/uv-receipt.json"

check() { have uv; }

run() {
  run_installer "$UV_INSTALLER_URL" UV_NO_MODIFY_PATH=1
  uv --version
}

upgrade() {
  if [ -f "$UV_RECEIPT" ]; then
    UV_NO_MODIFY_PATH=1 uv self update
  else
    info "no uv install receipt at $UV_RECEIPT; reinstalling with the standalone installer"
    run
  fi
}
