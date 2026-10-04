# summary: Install uv (Python tool manager) into ~/.local/bin
# check:   uv is on PATH
# notes:   https://astral.sh/uv/install.sh with UV_NO_MODIFY_PATH=1 (path-env owns
#          PATH). Needed because servers often lack pip/ensurepip without root.

check() { have uv; }

run() {
  run_installer https://astral.sh/uv/install.sh UV_NO_MODIFY_PATH=1
  uv --version
}

upgrade() { uv self update; }
