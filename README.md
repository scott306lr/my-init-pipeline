# my-init-pipeline

Brings a fresh Linux server to my working setup in one command, as my own user,
without root: gh, Claude Code with my synced `~/.claude`, Codex, herdr, uv,
uv-managed Pythons (with C headers), nvitop, zoxide, fzf, lazygit, delta, btop,
dust, the Hugging Face CLI and a Hugging Face cache folder, plus git's commit
identity. Words like **Step**, **Action**, **Check** and **Run** are defined in
[GLOSSARY.md](GLOSSARY.md).

## Set up a server

```bash
curl -fsSL https://raw.githubusercontent.com/scott306lr/my-init-pipeline/main/bootstrap.sh | bash
```

This clones the repo to `~/my-init-pipeline` and starts `./init.sh run`. On a
terminal it opens the **checklist**: Steps with work to do start ticked, so Enter
runs everything not yet done. Answer the questions that follow (gh login, the
Hugging Face cache folder), then the **Notes** at the end (log in to `claude`,
`codex login`, `source ~/.bashrc`). Re-running is safe: Steps whose Check passes
are skipped. `| bash -s -- -y` runs without the checklist.

Run it as yourself. The only Step that needs root, `hf-export`, asks for sudo
itself, and `init.sh` refuses to run as root outside a container or CI job.

## Update a server

```bash
cd ~/my-init-pipeline
./init.sh update run --upgrade   # pull this repo, then upgrade every installed Tool
./init.sh update run             # pull, then the checklist: tick a done Step to upgrade just that one
```

`update` only fast-forwards. On a checkout too old to have it, run
`git pull --ff-only` once by hand. A pull refuses while the checkout has local
edits that upstream also changed, typically `config.sh`: keep settings in the
environment instead (see Settings).

`--upgrade` runs each Tool's own updater and pulls `~/my-claude-setup` before
re-installing it. A setup clone with uncommitted work is left alone, with a Note
to publish it through `/sync-claude`.

## Share the Hugging Face cache

`hf-cache` puts Hugging Face data in one **cache folder**, laid out like
`HF_HOME` without the login token: `hub/` holds models and datasets downloaded
from the Hub (`HF_HUB_CACHE`), `datasets/` the datasets library's Arrow cache
(`HF_DATASETS_CACHE`). The token stays private in `~/.cache/huggingface`.

- **Your own folder.** Accept the suggested `/shared/huggingface_cache` (or name
  another). For a folder outside your home that you own, it asks whether to share
  it with every user; sharing needs no sudo.
- **Another user's folder.** One someone else owns is used as its owner shared
  it, through an ACL or a setgid group you belong to. Nothing is asked.
- **A folder only root can prepare**, or one every user should get by default
  (including users who never run this Pipeline): tick the optional `hf-export`
  too, or run `./init.sh run hf-export hf-cache`. `hf-export` runs first, prints
  its sudo command, and has root create, share and export the folder; `hf-cache`
  then offers it.

Pointing `hf-cache` at a new folder (`./init.sh run --force hf-cache hf-cache`)
moves your downloads there, merging, and keeping the new folder's copy where both
have one. Downloads move only out of a private cache of yours; a shared one stays
as it is.

Share only on a server whose users you trust: every user can change every cached
file, including model code that `trust_remote_code` runs.

Root can also share a folder without this Pipeline:
`curl -fsSL https://raw.githubusercontent.com/scott306lr/my-init-pipeline/main/admin/share-hf-cache.sh | sudo bash -s -- /shared/huggingface_cache`.
The script's header explains what it does as root and as a folder's owner.

## How a Run behaves

- **Order and parallelism.** `pipeline.conf` lists each Step, its Action
  (`actions/<action>.sh`) and the Steps it requires. Requirements decide the
  order; independent Steps run in parallel. `./init.sh list` shows every Step
  with its Check result.
- **Choosing Steps.** The checklist (gum `choose`; space ticks, `a` ticks all,
  Enter runs) appears on a terminal when no Step is named. Ticking a Step with
  work to do runs it, ticking a done Step upgrades it, ticking an Optional Step
  (marked `opt`) runs it. Naming Steps (`./init.sh run herdr`) runs them plus
  what they require.
- **Interactive Steps** take the terminal while background Steps continue. A Run
  without a terminal defers them, unless settings already answer their
  questions.
- **Optional Steps** (`hf-export`) run only when ticked, named or `--force`d.
  Otherwise the Run reports `○ optional` and what requires them still runs, like
  Debian's *Suggests*.
- **Output.** One line per Step, then Notes. Full logs are in
  `~/.local/state/my-init-pipeline/runs/latest/<step>.log`. An Interactive Step's
  output goes to the terminal, so its log holds only the result.

All commands and options: `./init.sh help`. One Step in full: `./init.sh describe <step>`.

## Settings

`config.sh` holds every setting with a comment saying what it does: the claude
setup repo, git identity, the Hugging Face cache folder (`HF_CACHE_DIR`,
`HF_CACHE_SHARED`, `HF_CACHE_SUGGESTED`) and the managed Python versions.
Override any of them from the environment for one Run, e.g.
`HF_CACHE_DIR=/data/hf HF_CACHE_SHARED=no ./init.sh run hf-cache`. An empty
environment value means "use the default"; to blank a setting, edit it in a
copy of `config.sh` and point `MIP_USER_CONFIG` at that copy (it replaces
`config.sh` whole).

## Adding or changing a Step

1. Write `actions/<action>.sh`. A header of `# key: value` lines, then functions:

   ```bash
   # summary: One line shown by `init.sh list`
   # check:   What the Check tests, in words
   # interactive: yes          # if it can need a human at the keyboard
   # optional: yes             # if it should run only when chosen
   # notes:   What a future reader needs to know (shown by `describe`)

   check()       { have mytool; }             # 0 = satisfied, 2 = not applicable here, else = to do
   run()         { run_installer https://example.com/install.sh; }
   upgrade()     { mytool self-update; }      # used by --upgrade and by ticking a done Step
   note()        { [ "$1" = upgraded ] || echo "Log in with: mytool login"; }   # $1 is ran or upgraded
   interactive() { [ -z "$MYTOOL_TOKEN" ]; }  # with `interactive: yes`: 0 while a human is still needed
   ```

2. Add `mytool  mytool-install  path-env` to `pipeline.conf`.
3. `./init.sh describe mytool`, then `./init.sh run mytool`.

The conventions every Action follows:

- `check()` and `interactive()` only look: `list`, `--dry-run` and the checklist
  call them. After `run()`, the Check runs again and decides success.
- Shell setup goes through `add_path`, `add_env`, `remove_env` and
  `add_shell_init`, which write `~/.config/my-init-pipeline/env.sh`; `~/.bashrc`
  only sources that file, from one marked block.
- Each function runs in a fresh `bash -eo pipefail` with `lib/common.sh` and
  `config.sh` loaded; the helpers are documented there. Logic two Actions share
  goes in `lib/` ([ADR 0001](docs/adr/0001-pure-bash-with-plain-text-step-table.md)).
- To install a Tool another way, point its Step at a different Action; the Step
  name and its dependents stay. Deleting a Step's line makes validation name
  whatever still requires it.

## Tests

```bash
tests/run.sh                            # bats: the runner with fake Actions, and each Action's logic
tests/admin.sh                          # cache sharing as root: in ubuntu:22.04 (on the runner in CI)
tests/e2e.sh                            # real installs in a throwaway HOME, twice; the second changes nothing
GH_TOKEN=$(gh auth token) tests/e2e.sh  # e2e including claude-config and herdr
tests/docker.sh [--interactive]         # e2e in ubuntu:22.04 as a non-root user without an SSH key
```

CI (`.github/workflows/ci.yml`) runs shellcheck, bats, a bootstrap dry run, the
sharing test and the non-interactive e2e. Its shellcheck is 0.8, which flags
`A && B || C` (SC2015) where newer versions do not; check with the same version:
`uvx --from shellcheck-py==0.8.0.4 shellcheck -x init.sh bootstrap.sh lib/*.sh actions/*.sh admin/*.sh tests/*.sh config.sh`.

## Known caveats

- herdr writes a SessionStart hook with this machine's absolute path into the
  shared `~/.claude/settings.json`. The `herdr` Step rewrites it to the `$HOME`
  form, and its Check notices if it comes back. Updates to herdr's hook script
  (`dotfiles/hooks/herdr-agent-state.sh`) are real changes: publish them with
  `/sync-claude`.
- The claude setup repo's `install.sh` exits 0 even when a plugin marketplace
  fails to register; `claude-config` turns those warnings into a Note.
- The checklist pins gum v0.17.0: gum v2 never ticks on space
  ([ADR 0002](docs/adr/0002-gum-step-picker.md)).

Design decisions: [docs/adr/](docs/adr/).
