# summary: Install dust (what is using the disk: `dust ~` / `dust -d 2 /data`)
# check:   dust is on PATH
# notes:   Latest GitHub release, static musl build. No published checksums, so
#          integrity rests on HTTPS from GitHub. Upgrade reinstalls the latest.

check() { have dust; }

run() {
  local tag
  tag="$(github_latest_tag bootandy/dust)"
  install_release_binary "https://github.com/bootandy/dust/releases/download/$tag/dust-$tag-$(machine_arch)-unknown-linux-musl.tar.gz" dust
  dust --version
}

upgrade() { run; }
