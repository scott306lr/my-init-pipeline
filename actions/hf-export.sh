# summary: Make the shared HF_HUB_CACHE every user's default, also for users who don't run this Pipeline (sudo)
# check:   not applicable for an HF_HUB_CACHE inside your home; else HF_HUB_CACHE is shared with every user and /etc/profile.d exports it
# interactive: yes
# optional: yes
# notes:   Optional, so it runs only when ticked in the checklist, named
#          (`./init.sh run hf-export`) or forced, never in a default or -y Run:
#          it is the one Step that needs root. It prints the sudo command, then
#          runs admin/share-hf-cache.sh as root for HF_HUB_CACHE: sharing it
#          (entries other users own included), the export in /etc/profile.d and
#          /etc/environment, and any parent folder others cannot enter. Its Check
#          does not wait for hf-cache: before hf-cache has recorded a directory
#          there is work to do, so the checklist offers it on a fresh server too.
#          It takes the terminal when sudo needs a password; with passwordless
#          (or freshly cached) sudo it runs without one, using `sudo -n`, so a
#          credential that expires between the check and the run fails at once
#          with "run it on a terminal" instead of hanging. Without sudo it
#          fails with the command to give an admin.

# A terminal only when sudo would ask for a password.
interactive() { ! sudo -n true 2>/dev/null; }

check() {
  local dir="${HF_HUB_CACHE:-}"   # env.sh is loaded: the hf-cache Step's value
  [ -n "$dir" ] || return 1       # hf-cache runs first and records it
  if in_home "$dir"; then return 2; fi   # a cache in your home is yours alone
  share_hf_cache --check "$dir" && share_hf_cache --exported "$dir"
}

run() {
  [ -n "${HF_HUB_CACHE:-}" ] || die "no HF_HUB_CACHE yet; run the hf-cache Step first"
  local -a cmd=(sudo bash "$MIP_ROOT/admin/share-hf-cache.sh" "$HF_HUB_CACHE")
  if [ ! -t 0 ]; then cmd=(sudo -n "${cmd[@]:1}"); fi   # no terminal: sudo must not prompt
  warn "hf-export needs sudo: ${cmd[*]}"
  "${cmd[@]}" && return
  if [ ! -t 0 ]; then die "sudo needs a password; run it on a terminal: ./init.sh run hf-export"; fi
  die "sudo failed; ask an admin to run: curl -fsSL https://raw.githubusercontent.com/scott306lr/my-init-pipeline/main/admin/share-hf-cache.sh | sudo bash -s -- $HF_HUB_CACHE"
}

note() { echo "Users pick up HF_HUB_CACHE=$HF_HUB_CACHE at their next login"; }
