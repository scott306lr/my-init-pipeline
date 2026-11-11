# summary: Make the shared Hugging Face cache folder every user's default, also for users who don't run this Pipeline (sudo)
# check:   not applicable for a cache folder inside your home; else the folder (holding HF_HUB_CACHE and HF_DATASETS_CACHE) is shared with every user and /etc/profile.d exports both
# interactive: yes
# optional: yes
# notes:   Optional, so it runs only when ticked in the checklist, named
#          (`./init.sh run hf-export`) or forced, never in a default or -y Run:
#          it is the one Step that needs root. It prints the sudo command, then
#          runs admin/share-hf-cache.sh as root for the cache folder: sharing it
#          (entries other users own included), the export of HF_HUB_CACHE and
#          HF_DATASETS_CACHE in /etc/profile.d and /etc/environment, and any
#          parent folder others cannot enter. Its Check does not wait for
#          hf-cache: before hf-cache has recorded a folder there is work to do,
#          so the checklist offers it on a fresh server too.
#          It takes the terminal when sudo needs a password; with passwordless
#          (or freshly cached) sudo it runs without one, using `sudo -n`, so a
#          credential that expires between the check and the run fails at once
#          with "run it on a terminal" instead of hanging. Without sudo it
#          fails with the command to give an admin.

# A terminal only when sudo would ask for a password.
interactive() { ! sudo -n true 2>/dev/null; }

check() {
  local root
  root="$(cache_root)"
  [ -n "$root" ] || return 1          # hf-cache runs first and records it
  if in_home "$root"; then return 2; fi   # a cache in your home is yours alone
  share_hf_cache --check "$root" && share_hf_cache --exported "$root"
}

run() {
  local root
  root="$(cache_root)"
  [ -n "$root" ] || die "no Hugging Face cache folder yet; run the hf-cache Step first"
  local -a cmd=(sudo bash "$MIP_ROOT/admin/share-hf-cache.sh" "$root")
  if [ ! -t 0 ]; then cmd=(sudo -n "${cmd[@]:1}"); fi   # no terminal: sudo must not prompt
  warn "hf-export needs sudo: ${cmd[*]}"
  "${cmd[@]}" && return
  if [ ! -t 0 ]; then die "sudo needs a password; run it on a terminal: ./init.sh run hf-export"; fi
  die "sudo failed; ask an admin to run: curl -fsSL https://raw.githubusercontent.com/scott306lr/my-init-pipeline/main/admin/share-hf-cache.sh | sudo bash -s -- $root"
}

note() { echo "Users pick up HF_HUB_CACHE and HF_DATASETS_CACHE in $(cache_root) at their next login"; }

# cache_root — the cache folder hf-cache recorded (env.sh is loaded), or nothing.
cache_root() { hf_cache_root "${HF_HUB_CACHE:-}" "${HF_DATASETS_CACHE:-}"; }
