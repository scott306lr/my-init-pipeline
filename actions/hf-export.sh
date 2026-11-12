# summary: Prepare and share the Hugging Face cache folder for every user, also users who don't run this Pipeline (sudo)
# check:   the cache folder is HF_CACHE_DIR, else the one in effect, else HF_CACHE_SUGGESTED; not applicable when there is none or it is inside your home; else it is shared with every user and both /etc/profile.d and /etc/environment export its hub/ and datasets/
# interactive: yes
# optional: yes
# notes:   Optional, so it runs only when ticked in the checklist, named
#          (`./init.sh run hf-export`) or forced, never in a default or -y Run:
#          it is the one Step that needs root. It runs before hf-cache, so
#          root can first prepare a folder you could not create or write to
#          (one root made, say): it asks for the folder (HF_CACHE_DIR answers;
#          the default is the one already in effect, else HF_CACHE_SUGGESTED),
#          prints the sudo command, then runs admin/share-hf-cache.sh as root:
#          creating the folder with hub/ and datasets/, sharing it (entries
#          other users own included), opening any parent others cannot enter,
#          and exporting HF_HUB_CACHE and HF_DATASETS_CACHE in /etc/profile.d
#          and /etc/environment. hf-cache then offers that folder. It takes the
#          terminal when sudo needs a password; with passwordless (or freshly
#          cached) sudo it runs without one, using `sudo -n`, so a credential
#          that expires between the check and the run fails at once with "run
#          it on a terminal" instead of hanging. Without sudo it fails with the
#          command to give an admin.

# shellcheck source=lib/hf-cache.sh
. "$MIP_ROOT/lib/hf-cache.sh"

# A terminal only when sudo would ask for a password.
interactive() { ! sudo -n true 2>/dev/null; }

check() {
  local folder
  folder="$(default_folder)" || return 1
  [ -n "$folder" ] || return 2
  hf_cache_state "$folder" || return 1
  [ "${HF_STATE[home]}" = no ] || return 2   # a cache in your home is yours alone
  [ "${HF_STATE[shared]}" != none ] && [ "${HF_STATE[exported]}" = yes ]
}

run() {
  local folder
  folder="$(default_folder)" || return 1
  if [ -z "$HF_CACHE_DIR" ]; then
    folder="$(hf_ask_folder "Folder to share with every user of this server (holds hub/ and datasets/)" "$folder")" || return 1
  fi
  hf_cache_state "$folder" || return 1
  if [ "${HF_STATE[home]}" = yes ]; then die "$folder is in your home: a cache there is yours alone, so there is nothing to share"; fi
  local -a cmd=(sudo bash "$MIP_ROOT/admin/share-hf-cache.sh" "$folder")
  if [ ! -t 0 ]; then cmd=(sudo -n "${cmd[@]:1}"); fi   # no terminal: sudo must not prompt
  warn "hf-export needs sudo: ${cmd[*]}"
  "${cmd[@]}" && return
  if [ ! -t 0 ]; then die "sudo needs a password; run it on a terminal: ./init.sh run hf-export"; fi
  die "sudo failed; ask an admin to run: curl -fsSL https://raw.githubusercontent.com/scott306lr/my-init-pipeline/main/admin/share-hf-cache.sh | sudo bash -s -- $folder"
}

note() { echo "Every user gets HF_HUB_CACHE and HF_DATASETS_CACHE in $(hf_admin --exported-folder) from their next login"; }

# default_folder — the cache folder already decided (hf_cache_resolve), else
# HF_CACHE_SUGGESTED (root can create it wherever it is).
default_folder() {
  local f
  f="$(hf_cache_resolve)" || return 1
  printf '%s\n' "${f:-${HF_CACHE_SUGGESTED:-}}"
}
