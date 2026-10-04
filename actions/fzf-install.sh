# summary: Install fzf (fuzzy finder: Ctrl-R history, Ctrl-T files, Alt-C dirs; powers zoxide's zi)
# check:   fzf is on PATH and its `fzf --bash` hook is in the managed env file
# notes:   Latest GitHub release binary, verified against the release's checksums
#          file. Key bindings come from `fzf --bash` (fzf >= 0.48), added for
#          interactive shells via add_shell_init. Upgrade reinstalls the latest.

FZF_INIT='command -v fzf >/dev/null && eval "$(fzf --bash)"'

check() { have fzf && env_has_shell_init "$FZF_INIT"; }

run() {
  have fzf || install_fzf
  add_shell_init "$FZF_INIT"
}

upgrade() { install_fzf; }

install_fzf() {
  local tag ver arch file base
  tag="$(github_latest_tag junegunn/fzf)"; ver="${tag#v}"
  case "$(machine_arch)" in x86_64) arch=amd64 ;; aarch64) arch=arm64 ;; esac
  file="fzf-$ver-linux_$arch.tar.gz"
  base="https://github.com/junegunn/fzf/releases/download/$tag"
  install_release_binary "$base/$file" fzf "$(release_sha256 "$base/fzf_${ver}_checksums.txt" "$file")"
  fzf --version
}
