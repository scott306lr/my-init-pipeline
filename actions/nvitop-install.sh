# summary: Install nvitop (GPU monitor) as an isolated uv tool; skipped without nvidia-smi
# check:   not applicable without nvidia-smi; otherwise nvitop is on PATH
# notes:   `uv tool install nvitop` puts a shim in ~/.local/bin.

check() {
  have nvidia-smi || return 2
  have nvitop
}

run() {
  uv tool install nvitop
  nvitop --version
}

upgrade() { uv tool upgrade nvitop; }
