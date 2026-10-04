# summary: Install btop (CPU, memory, disk I/O and network monitor; nvitop covers GPUs)
# check:   btop is on PATH
# notes:   Latest GitHub release, static musl build; only the binary is installed
#          (bundled themes are optional). No published checksums, so integrity
#          rests on HTTPS from GitHub. Upgrade reinstalls the latest.

check() { have btop; }

run() {
  local tag
  tag="$(github_latest_tag aristocratos/btop)"
  install_release_binary "https://github.com/aristocratos/btop/releases/download/$tag/btop-$(machine_arch)-unknown-linux-musl.tar.gz" btop
  btop --version
}

upgrade() { run; }
