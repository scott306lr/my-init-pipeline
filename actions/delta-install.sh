# summary: Install delta (syntax-highlighted git diffs) and make it git's pager unless one is set
# check:   delta is on PATH and git has a core.pager (delta, or one you chose)
# notes:   Latest GitHub release binary (static musl on x86_64; the project publishes
#          no checksums, so integrity rests on HTTPS from GitHub). Sets, in
#          ~/.gitconfig, core.pager=delta, interactive.diffFilter and delta.navigate,
#          but only when core.pager is unset: an existing pager choice is kept.
#          Upgrade reinstalls the latest binary.

check() { have delta && [ -n "$(git config --global --get core.pager)" ]; }

run() {
  have delta || install_delta
  if [ -z "$(git config --global --get core.pager)" ]; then
    git config --global core.pager delta
    git config --global interactive.diffFilter 'delta --color-only'
    git config --global delta.navigate true
    info "git now pages diffs through delta"
  fi
}

upgrade() { install_delta; }

install_delta() {
  local tag triple
  tag="$(github_latest_tag dandavison/delta)"
  case "$(machine_arch)" in
    x86_64) triple=x86_64-unknown-linux-musl ;;
    aarch64) triple=aarch64-unknown-linux-gnu ;;   # no musl build for aarch64
  esac
  install_release_binary "https://github.com/dandavison/delta/releases/download/$tag/delta-$tag-$triple.tar.gz" delta
  delta --version
}
