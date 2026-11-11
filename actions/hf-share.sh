# summary: Share HF_HUB_CACHE_DIR with the users of group HF_SHARE_GROUP (off unless HF_SHARE_GROUP is set)
# check:   not applicable while HF_SHARE_GROUP is empty; else the group exists with you in it, the directory has that group, setgid and its default ACL, and /etc/profile.d exports HF_HUB_CACHE for it
# interactive: yes
# sudo: yes
# notes:   The one Step that needs root, so it is opt-in: set HF_SHARE_GROUP (and
#          HF_HUB_CACHE_DIR) in config.sh. It runs admin/share-hf-cache.sh with
#          sudo, adding you to the group, and prints that command first. It asks
#          for a password only when sudo needs one, so passwordless sudo also
#          works without a terminal. On a server someone already shared, the
#          Check passes without sudo for every member of the group; a user who
#          is not a member and has no sudo gets the command to hand an admin.
#          New group membership takes effect at your next login.

HF_SHARE_PROFILE=/etc/profile.d/hf-hub-cache.sh

interactive() { ! sudo -n true 2>/dev/null; }

check() {
  [ -n "$HF_SHARE_GROUP" ] || return 2
  local dir="$HF_HUB_CACHE_DIR"
  [ -n "$dir" ] && [ -d "$dir" ] && in_group &&
    [ "$(stat -c %G "$dir")" = "$HF_SHARE_GROUP" ] && [ -g "$dir" ] &&
    getfacl -p "$dir" 2>/dev/null | grep -qx "default:group:$HF_SHARE_GROUP:rwx" &&
    [ "$(cat "$HF_SHARE_PROFILE" 2>/dev/null)" = "$(printf 'export HF_HUB_CACHE=%q' "$dir")" ]
}

run() {
  [ -n "$HF_HUB_CACHE_DIR" ] || die "HF_SHARE_GROUP is set, so set HF_HUB_CACHE_DIR to the directory to share"
  local -a cmd=(sudo bash "$MIP_ROOT/admin/share-hf-cache.sh" "$HF_HUB_CACHE_DIR" "$HF_SHARE_GROUP" "$(id -un)")
  warn "hf-share needs sudo: ${cmd[*]}"
  "${cmd[@]}" || die "sudo failed; without sudo, ask an admin to run: curl -fsSL https://raw.githubusercontent.com/scott306lr/my-init-pipeline/main/admin/share-hf-cache.sh | sudo bash -s -- $HF_HUB_CACHE_DIR $HF_SHARE_GROUP $(id -un)"
}

note() {
  # This Run's processes predate the new membership; a fresh login picks it up.
  if ! id -nG | tr ' ' '\n' | grep -qx "$HF_SHARE_GROUP"; then
    echo "Log in again so your shells join group $HF_SHARE_GROUP (needed to write $HF_HUB_CACHE_DIR)"
  fi
}

# in_group — true if the group database lists you in HF_SHARE_GROUP (true from
# the moment you are added, unlike `id -nG` of an already running shell).
in_group() {
  local me members
  me="$(id -un)"
  members="$(getent group "$HF_SHARE_GROUP" | cut -d: -f4)" || return 1
  [[ ",$members," == *",$me,"* ]] || [ "$(id -gn)" = "$HF_SHARE_GROUP" ]
}
