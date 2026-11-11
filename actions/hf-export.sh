# summary: Make the shared HF_HUB_CACHE every user's default, also for users who don't run this Pipeline (sudo)
# check:   not applicable unless HF_HUB_CACHE is a shared directory; else /etc/profile.d exports it
# interactive: yes
# optional: yes
# notes:   Optional, so it runs only when ticked in the picker, named
#          (`./init.sh run hf-export`) or forced, never in a default or -y Run:
#          it is the one Step that needs root. It prints the sudo command, then
#          runs admin/share-hf-cache.sh as root for HF_HUB_CACHE: the export in
#          /etc/profile.d and /etc/environment, entries other users own, and any
#          parent folder others cannot enter. It needs a terminal only when sudo
#          asks for a password. Without sudo it fails with the command to give
#          an admin.

SHARE="$MIP_ROOT/admin/share-hf-cache.sh"

interactive() { ! sudo -n true 2>/dev/null; }

check() {
  local dir="${HF_HUB_CACHE:-}"   # env.sh is loaded: the hf-cache Step's value
  [ -n "$dir" ] && bash "$SHARE" --check "$dir" || return 2
  bash "$SHARE" --exported "$dir"
}

run() {
  local -a cmd=(sudo bash "$SHARE" "$HF_HUB_CACHE")
  warn "hf-export needs sudo: ${cmd[*]}"
  "${cmd[@]}" || die "sudo failed; ask an admin to run: curl -fsSL https://raw.githubusercontent.com/scott306lr/my-init-pipeline/main/admin/share-hf-cache.sh | sudo bash -s -- $HF_HUB_CACHE"
}

note() { echo "Users pick up HF_HUB_CACHE=$HF_HUB_CACHE at their next login"; }
