# summary: Set git's global user.name and user.email (GIT_USER_NAME/EMAIL in config.sh) unless already set
# check:   git config --global has both user.name and user.email (any value)
# notes:   Each value is written to ~/.gitconfig only when it is unset, so an
#          identity you configured by hand is kept. Fails if a value is still
#          needed and the setting is empty. Without this, the first commit on a
#          fresh machine stops at "Please tell me who you are".

check() {
  [ -n "$(git config --global --get user.name)" ] && [ -n "$(git config --global --get user.email)" ]
}

run() {
  set_identity user.name "$GIT_USER_NAME" GIT_USER_NAME
  set_identity user.email "$GIT_USER_EMAIL" GIT_USER_EMAIL
}

# set_identity KEY VALUE SETTING — write KEY=VALUE globally unless KEY is set.
set_identity() {
  local key="$1" value="$2" setting="$3"
  [ -n "$(git config --global --get "$key")" ] && return 0
  [ -n "$value" ] || die "$key is unset; set $setting in config.sh"
  git config --global "$key" "$value"
  info "git $key = $value"
}
