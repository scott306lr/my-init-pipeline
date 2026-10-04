# summary: Put ~/.local/bin on PATH via the managed env file, sourced from ~/.bashrc
# check:   ~/.local/bin exists, env.sh lists it, and ~/.bashrc has the marker block
# notes:   The only edit to ~/.bashrc is one marked block; every other Step adds
#          PATH entries with add_path, which writes ~/.config/my-init-pipeline/env.sh.
#          Runs first so the codex and uv installers see ~/.local/bin on PATH and
#          leave rc files alone.

check() {
  [ -d "$HOME/.local/bin" ] && env_has_path '$HOME/.local/bin' && bashrc_hooked
}

run() {
  mkdir -p "$HOME/.local/bin"
  add_path '$HOME/.local/bin'
  hook_bashrc
}
