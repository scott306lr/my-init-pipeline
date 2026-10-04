# summary: Install GitHub CLI (gh) to ~/.local/opt/gh without root, linked into ~/.local/bin
# check:   gh is on PATH
# notes:   Follows https://blog.melashri.net/micro/gh-no-root/, but verifies the
#          tarball against the release's checksums file and never edits ~/.bashrc
#          (path-env owns PATH). Upgrade reinstalls only if a newer release exists.

check() { have gh; }

run() {
  local arch tag ver tmp name
  case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
    armv7l) arch=armv6 ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac
  tag="$(github_latest_tag cli/cli)"
  ver="${tag#v}"
  name="gh_${ver}_linux_${arch}"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  info "downloading gh $ver ($arch)"
  fetch "https://github.com/cli/cli/releases/download/$tag/$name.tar.gz" "$tmp/$name.tar.gz"
  fetch "https://github.com/cli/cli/releases/download/$tag/gh_${ver}_checksums.txt" "$tmp/checksums.txt"
  (cd "$tmp" && grep " $name.tar.gz\$" checksums.txt | sha256sum -c -)
  tar -xzf "$tmp/$name.tar.gz" -C "$tmp"
  mkdir -p "$HOME/.local/opt" "$HOME/.local/bin"
  rm -rf "$HOME/.local/opt/gh"
  mv "$tmp/$name" "$HOME/.local/opt/gh"
  ln -sfn "$HOME/.local/opt/gh/bin/gh" "$HOME/.local/bin/gh"
  gh --version
}

upgrade() {
  local current latest
  current="$(gh --version | sed -n '1s/^gh version \([^ ]*\).*/\1/p')"
  latest="$(github_latest_tag cli/cli)"
  if [ "v$current" = "$latest" ]; then
    info "gh $current is the latest"
  else
    info "gh $current -> ${latest#v}"
    run
  fi
}
