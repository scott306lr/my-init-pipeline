# summary: Install lazygit (terminal UI for git: review, stage and commit agent-made changes)
# check:   lazygit is on PATH
# notes:   Latest GitHub release binary, verified against the release's checksums.txt.
#          Upgrade reinstalls the latest.

check() { have lazygit; }

run() {
  local tag ver arch file base
  tag="$(github_latest_tag jesseduffield/lazygit)"; ver="${tag#v}"
  case "$(machine_arch)" in x86_64) arch=x86_64 ;; aarch64) arch=arm64 ;; esac
  file="lazygit_${ver}_linux_$arch.tar.gz"
  base="https://github.com/jesseduffield/lazygit/releases/download/$tag"
  install_release_binary "$base/$file" lazygit "$(release_sha256 "$base/checksums.txt" "$file")"
  lazygit --version
}

upgrade() { run; }
