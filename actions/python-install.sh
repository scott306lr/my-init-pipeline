# summary: Install uv-managed CPython (MANAGED_PYTHON_VERSIONS in config.sh) and make uv prefer it over system Pythons
# check:   each version in MANAGED_PYTHON_VERSIONS is a uv-managed install, and env.sh exports UV_PYTHON_PREFERENCE=only-managed
# notes:   `uv python install` (python-build-standalone builds under
#          ~/.local/share/uv/python). Unlike a system Python without its -dev
#          package, these ship include/python3.X/Python.h, so C extensions
#          (and Triton's JIT) compile without root. UV_PYTHON_PREFERENCE=only-managed
#          stops `uv venv` / `uv sync` from picking /usr/bin/python3.X; pass
#          --python /usr/bin/python3.X to use a system one anyway. uv also links
#          python3.X into ~/.local/bin, ahead of /usr/bin on PATH. The Check uses
#          `uv python find --system --python-preference only-managed`, so a venv
#          in the current directory doesn't count (--managed-python would clash
#          with the exported UV_PYTHON_PREFERENCE).

check() {
  local v
  [ -n "$MANAGED_PYTHON_VERSIONS" ] || return 1
  for v in $MANAGED_PYTHON_VERSIONS; do
    managed_python "$v" >/dev/null 2>&1 || return 1
  done
  env_has_env UV_PYTHON_PREFERENCE only-managed
}

run() {
  local v
  [ -n "$MANAGED_PYTHON_VERSIONS" ] || die "MANAGED_PYTHON_VERSIONS is empty; set it in config.sh"
  # shellcheck disable=SC2086 # a space-separated list of versions
  uv python install $MANAGED_PYTHON_VERSIONS
  add_env UV_PYTHON_PREFERENCE only-managed
  for v in $MANAGED_PYTHON_VERSIONS; do info "$v: $(managed_python "$v")"; done
}

# shellcheck disable=SC2086
upgrade() { uv python upgrade $MANAGED_PYTHON_VERSIONS; }

# managed_python V — path of the uv-managed interpreter for V; fails if none.
managed_python() { uv python find --system --python-preference only-managed "$1"; }

note() { echo "Python: venvs built on a system Python keep it; recreate them (uv venv / uv sync) to get a managed one with headers."; }
