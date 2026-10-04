# summary: Log gh in to GitHub (needed to clone the private claude setup repo)
# check:   gh auth status succeeds
# interactive: yes
# notes:   Runs `gh auth login` on the terminal; choose the protocol you clone with.
#          A GH_TOKEN in the environment also satisfies the Check.

check() { gh auth status >/dev/null 2>&1; }

run() { gh auth login; }
