# my-init-pipeline

One command brings a fresh Linux server to my working setup, as my own user, no
root needed: gh, Claude Code (with my synced `~/.claude`), Codex, herdr, uv and
uv-managed Pythons, nvitop, zoxide, fzf, lazygit, delta, btop, dust, the Hugging
Face CLI with a shared cache folder, and git's commit identity.

## Quick start

On a new server, as yourself (not root):

```bash
curl -fsSL https://raw.githubusercontent.com/scott306lr/my-init-pipeline/main/bootstrap.sh | bash
```

A checklist opens with everything still to do ticked. Press **Enter** to run it
(**space** ticks or unticks a line). Answer the questions that come up (gh
login, Hugging Face cache folder), then follow the **Notes** printed at the end,
usually:

```bash
source ~/.bashrc
claude          # then /login
codex login
```

Running it again is safe: anything already done is skipped.

## Everyday commands

Run these from `~/my-init-pipeline`:

```bash
cd ~/my-init-pipeline
```

| To | Run |
|---|---|
| Pick what to install or upgrade | `./init.sh run` |
| Install everything, no checklist | `./init.sh run -y` |
| Update this repo, then upgrade every installed tool | `./init.sh update run --upgrade` |
| Update this repo, then pick in the checklist | `./init.sh update run` |
| Install or redo one Step (and what it needs) | `./init.sh run herdr` |
| Redo a Step that is already done | `./init.sh run --force codex` |
| See every Step and whether it is done | `./init.sh list` |
| Read what one Step does | `./init.sh describe hf-cache` |
| Preview what a Run would do to each Step, changing nothing | `./init.sh run --dry-run` |
| All commands and options | `./init.sh help` |

In the checklist, ticking a Step that is already done upgrades it, and Steps
marked `opt` run only when you tick them.

## Hugging Face cache

Models and datasets go to one **cache folder** (`hub/` and `datasets/` inside
it), so all users of a server can share downloads. Your login token stays
private in `~/.cache/huggingface`. Pick the case that fits:

**Your own folder, shared with every user** (no sudo needed):

```bash
HF_CACHE_DIR=/shared/huggingface_cache HF_CACHE_SHARED=yes ./init.sh run hf-cache
```

**A folder only root can create, or one every user should get by default** (asks
for your sudo password):

```bash
HF_CACHE_DIR=/shared/huggingface_cache ./init.sh run hf-export hf-cache
```

**A folder someone else already shared** (uses it as it is):

```bash
HF_CACHE_DIR=/mnt/shared/huggingface_cache ./init.sh run hf-cache
```

**Just for you**, inside your home:

```bash
HF_CACHE_DIR=$HOME/.cache/huggingface ./init.sh run hf-cache
```

**Move to another folder** (your downloads move with you; a shared folder keeps
its files). `--force hf-cache` redoes the Step even though it is done; the
second `hf-cache` is the Step to run:

```bash
HF_CACHE_DIR=/data/hf ./init.sh run --force hf-cache hf-cache
```

**Root, without this repo** (shares the folder and makes it every user's default):

```bash
curl -fsSL https://raw.githubusercontent.com/scott306lr/my-init-pipeline/main/admin/share-hf-cache.sh | sudo bash -s -- /shared/huggingface_cache
```

Share only on a server whose users you trust: anyone can change any cached file,
including model code that `trust_remote_code` runs.

## Troubleshooting

**A Step failed.** Read its log, then run it again:

```bash
cat ~/.local/state/my-init-pipeline/runs/latest/<step>.log
./init.sh run <step>
```

An Interactive Step (gh-auth, hf-cache, hf-export) prints to your terminal; its
log holds only the result.

**"don't run my-init-pipeline as root".** Run it as yourself, without sudo. Steps
that need root ask for your password themselves.

**`update` says it cannot fast-forward.** Your checkout has local changes that
upstream also changed. See them, then keep or drop them:

```bash
cd ~/my-init-pipeline
git status                     # what is changed
git stash && ./init.sh update  # set the changes aside, then update (git stash pop brings them back)
```

**New tools aren't found, or an old `HF_HOME` is still set.** Open a new
terminal, or:

```bash
source ~/.bashrc
unset HF_HOME
```

Terminal multiplexers (tmux, herdr) keep the environment they started with;
restart their server (`herdr server stop`, then `herdr`) for new panes to pick
up changes.

**`claude-config` didn't pull my setup changes.** `~/my-claude-setup` has
uncommitted work; publish it with `/sync-claude`, then `./init.sh run --upgrade`.

## Settings

Settings live in `config.sh`, each with a comment saying what it does: the
claude setup repo, git identity, the Hugging Face cache folder and the Python
versions. Give one for a single Run by putting it in front of the command, as in
the examples above:

```bash
MANAGED_PYTHON_VERSIONS="3.11 3.12" ./init.sh run python
```

Prefer this over editing `config.sh`: a local edit there blocks `update` when
upstream changes the file. An empty value (`VAR= ./init.sh …`) means "use the
default".

## How it works

`pipeline.conf` lists each **Step**, the **Action** that does its work
(`actions/<action>.sh`) and the Steps it requires. A **Run** checks each Step and
runs only what isn't done, in dependency order and in parallel where it can.
**Interactive** Steps take the terminal; without one they wait for a later Run.
**Optional** Steps (`hf-export`, the only one using sudo) run only when you
choose them. `./init.sh run --dry-run` prints the **Plan**: for each Step,
whether the Run would run it, upgrade it, or skip it as done, na (does not
apply on this server), optional or deferred. Vocabulary: [GLOSSARY.md](GLOSSARY.md). Design decisions:
[docs/adr/](docs/adr/).

## Adding a Step

1. Write `actions/mytool-install.sh`:

   ```bash
   # summary: Install mytool into ~/.local/bin
   # check:   mytool is on PATH

   check()   { have mytool; }       # 0 = done, 2 = not applicable here, else = to do
   run()     { run_installer https://example.com/install.sh; }
   upgrade() { mytool self-update; }
   note()    { [ "$1" = upgraded ] || echo "Log in with: mytool login"; }
   ```

2. Add it to `pipeline.conf`, with the Steps it needs:

   ```
   mytool          mytool-install   path-env
   ```

3. Try it:

   ```bash
   ./init.sh describe mytool
   ./init.sh run mytool
   ```

Conventions every Action follows:

- `check()` (and `interactive()`, if defined) only look, never change anything;
  after `run()` the Check runs again and decides success.
- Change the shell setup only with `add_path`, `add_env`, `remove_env` and
  `add_shell_init`; they write `~/.config/my-init-pipeline/env.sh`, which
  `~/.bashrc` sources.
- Each function runs in a fresh `bash -eo pipefail` with `lib/common.sh`
  (helpers, documented there) and `config.sh` loaded. Logic two Actions share
  goes in `lib/`, in a file they source (as `lib/hf-cache.sh` is).
- `upgrade()`, `note()` and `interactive()` are optional: define one only when
  the Action has something to do there. The runner asks whether an Action
  defines a function before calling it; calling one it lacks is status 127.
- Header keys: `interactive: yes` if it may need a human, `optional: yes` if it
  should run only when chosen, `notes:` for anything `describe` should show.

## Tests

```bash
tests/run.sh                            # unit tests (bats 1.14.0, fetched into tests/.bats)
tests/admin.sh                          # cache sharing as root, in a container
tests/e2e.sh                            # real installs in a throwaway HOME
GH_TOKEN=$(gh auth token) tests/e2e.sh  # e2e including claude-config and herdr
tests/docker.sh                         # e2e in a clean ubuntu:22.04 container
```

CI uses shellcheck 0.8, which is stricter than newer versions on `A && B || C`.
Check with the same one before pushing:

```bash
uvx --from shellcheck-py==0.8.0.4 shellcheck -x init.sh bootstrap.sh lib/*.sh actions/*.sh admin/*.sh tests/*.sh config.sh
```

## Known caveats

- herdr writes a SessionStart hook with this machine's absolute path into the
  shared `~/.claude/settings.json`. The `herdr` Step rewrites it to the `$HOME`
  form. Changes to herdr's hook script are real: publish them with `/sync-claude`.
- The claude setup repo's `install.sh` exits 0 even when a plugin marketplace
  fails to register; `claude-config` reports those as a Note.
- The checklist uses gum v0.17.0, because gum v2 ignores the space key
  ([ADR 0002](docs/adr/0002-gum-step-picker.md)).
