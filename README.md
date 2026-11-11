# my-init-pipeline

One command to bring a fresh Linux server to my working setup, **without root**:
gh, Claude Code (plus my synced `~/.claude`), Codex, herdr, uv, nvitop, zoxide,
fzf, lazygit, delta, btop, dust and the Hugging Face CLI, plus uv-managed Pythons
(with C headers), and sets git's commit identity.

```bash
curl -fsSL https://raw.githubusercontent.com/scott306lr/my-init-pipeline/main/bootstrap.sh | bash
```

This clones the repo to `~/my-init-pipeline` and runs `./init.sh run`, which on a
terminal first shows a checklist of Steps to pick from (Enter runs everything not
yet done; `| bash -s -- -y` skips it). Safe to re-run:
Steps that are already satisfied are skipped. Vocabulary is in [GLOSSARY.md](GLOSSARY.md).

## The Pipeline

`pipeline.conf` declares one **Step** per line: its name, the **Action** that does
the work (`actions/<action>.sh`), and the Steps it requires.

```
path-env        path-env
gh              gh-install       path-env
gh-auth         gh-auth          gh                 # interactive
claude          claude-install   path-env
claude-config   claude-config    claude gh-auth
codex           codex-install    path-env
uv              uv-install       path-env
nvitop          nvitop-install   uv
python          python-install   uv            # managed CPython (with headers); uv prefers it
zoxide          zoxide-install   path-env
fzf             fzf-install      path-env
lazygit         lazygit-install  path-env
delta           delta-install    path-env      # also sets git's pager, if none is set
git-identity    git-identity                   # user.name / user.email, if unset
btop            btop-install     path-env
dust            dust-install     path-env
hf              hf-install       uv
hf-cache        hf-cache         path-env      # interactive unless HF_HUB_CACHE_DIR (and, outside home, HF_HUB_CACHE_SHARED) is set
hf-export       hf-export        hf-cache      # optional, sudo: the shared cache becomes every user's default
herdr           herdr-install    claude-config codex
```

Dependencies decide the order; Steps with no dependency between them run in parallel.
Interactive Steps (like `gh-auth`) take the terminal while background Steps keep
going; anything that requires them waits. A Run without a terminal defers them,
unless a setting already answers the question (`hf-cache` with `HF_HUB_CACHE_DIR` and `HF_HUB_CACHE_SHARED`).

Optional Steps (like `hf-export`, the only one that uses sudo) are offered but
never run unless you choose them: tick one in the checklist (marked `opt`), or
name it (`./init.sh run hf-export`). A default or `-y` Run reports them as
`○ optional`, and what requires them still runs, like Debian's *Suggests*.

## Commands

| Command | |
|---|---|
| `./init.sh run` | On a terminal, pick Steps from a checklist, then run them (plus what they require). Steps with work to do start ticked; ticking a Step that is already done upgrades it (re-runs it if it has no `upgrade()`) |
| `./init.sh run -y` | Run the whole Pipeline without the checklist (also what happens without a terminal) |
| `./init.sh run herdr` | Run `herdr` plus whatever it requires that isn't satisfied yet |
| `./init.sh run --force codex` | Re-run a Step even though its Check passes |
| `./init.sh run --upgrade` | Upgrade everything already installed: each Tool with its own updater, and the claude setup repo pulled (fast-forward only) and re-installed |
| `./init.sh update` | Pull the latest my-init-pipeline (fast-forward only). `./init.sh update run --upgrade` updates the pipeline, then everything it installed |
| `./init.sh run --dry-run` | Show the plan and current Check results; change nothing |
| `./init.sh run -j 1` | One Step at a time (easier to debug) |
| `./init.sh run --non-interactive` | Skip Interactive Steps and what requires them |
| `./init.sh list` | Step → Action → requires → Check result → summary |
| `./init.sh describe <step>` | Everything about one Step |

If a Run changed your shell setup (PATH entries your current shell lacks, or a
new hook such as zoxide's), it ends by printing `source ~/.bashrc` (a script
can't update the shell that started it; new terminals pick it up on their own).

Each Run prints one line per Step and ends with **Notes**: things left for you,
such as logging in to `claude` and `codex`. Full logs go to
`~/.local/state/my-init-pipeline/runs/latest/<step>.log`.

## Adding, changing and removing Steps

1. Write `actions/<action>.sh`:

   ```bash
   # summary: One line shown by `init.sh list`
   # check:   What the Check tests, in words
   # interactive: yes          # only if it needs a human at the keyboard
   # optional: yes             # only if it should run just when chosen
   # notes:   Anything a future you needs to know (shown by `describe`)

   check()   { have mytool; }          # 0 = satisfied, 2 = not applicable here, else = to do
   run()     { run_installer https://example.com/install.sh; }
   upgrade() { mytool self-update; }   # optional: --upgrade, or ticking a done Step
   note()    { [ "$1" = upgraded ] || echo "Remember to ..."; }  # optional, shown after a Run where
                                       # it ran or upgraded; $1 says which
   interactive() { [ -z "$MYTOOL_TOKEN" ]; }  # optional, with `interactive: yes`: 0 while a human is still needed
   ```

2. Add a line to `pipeline.conf`: `mytool  mytool-install  path-env`.
3. `./init.sh describe mytool`, then `./init.sh run mytool`.

Rules for Actions:
- **Checks must have no side effects.** `list` and `--dry-run` call them, and the
  same goes for `interactive()`.
- After `run`, the runner runs the Check again, and the Step only succeeds if it passes.
- Never edit rc files. Use `add_path '$HOME/some/bin'` for PATH,
  `add_env VAR '$HOME/value'` for an exported variable, and
  `add_shell_init '<line>'` for interactive-only setup (e.g. `eval "$(tool init bash)"`).
  All three record into `~/.config/my-init-pipeline/env.sh`. `~/.bashrc` sources that file through one
  marked block.
- Each function runs in a fresh `bash -eo pipefail`, with `lib/common.sh` and `config.sh`
  loaded. Helpers: `have`, `info`, `warn`, `die`, `fetch`, `run_installer`,
  `github_latest_tag`, `machine_arch`, `release_sha256`, `install_release_binary`
  (download a GitHub release tarball, verify its sha256 when published, install
  one binary into `~/.local/bin` or a given folder), `add_path`, `add_env`,
  `remove_env`, `add_shell_init`, `in_home` (a path is in your home),
  `share_hf_cache` (`admin/share-hf-cache.sh`), `root_outside_container`.

To swap how something is installed, point its Step at a different Action. The
Step name and every dependency on it stay unchanged. To remove a Step, delete its
line; validation reports anything that still requires it.

## Settings

`config.sh` holds the settings for `claude-config`, `git-identity`, `hf-cache` and `python`. Each one can also be overridden from the environment:

| Variable | Default | |
|---|---|---|
| `CLAUDE_SETUP_REPO` | `scott306lr/my-claude-setup` | the private copy of [my-portable-claude](https://github.com/scott306lr/my-portable-claude) |
| `CLAUDE_SETUP_DIR` | `~/my-claude-setup` | where it is cloned |
| `CLAUDE_SETUP_PROTOCOL` | `https` | `https` (via gh's credential helper) or `ssh` (needs a key on GitHub) |
| `CLAUDE_SETUP_REF` | *(default branch)* | branch for a fresh clone, e.g. to test a change before merging it |
| `GIT_USER_NAME` | `scott306lr` | git `user.name`, written only if `~/.gitconfig` has none |
| `GIT_USER_EMAIL` | `scott306lr@gmail.com` | git `user.email`, likewise |
| `HF_HUB_CACHE_DIR` | *(empty: asked on the terminal, suggesting `HF_HUB_CACHE_SUGGESTED`)* | exported as `HF_HUB_CACHE` (model and dataset downloads) for every shell, e.g. `/data/hf/hub`. `HF_HOME` is left at `~/.cache/huggingface`, so the token stays private. Change it later with `./init.sh run --force hf-cache hf-cache`; existing downloads are not moved |
| `HF_HUB_CACHE_SUGGESTED` | `/shared/huggingface_cache/hub` | what that question offers when no `HF_HUB_CACHE` is in effect yet, if you can create it and `~/.cache/huggingface/hub` holds no downloads (else it offers that); Enter takes it |
| `HF_HUB_CACHE_SHARED` | *(empty: asked)* | `yes` shares an `HF_HUB_CACHE_DIR` outside your home with every user of the server, `no` keeps it yours (see below) |
| `MANAGED_PYTHON_VERSIONS` | `3.10 3.12` | installed with `uv python install`; `UV_PYTHON_PREFERENCE=only-managed` is exported so `uv venv` / `uv sync` use them (they have `Python.h`) instead of a system Python that may lack its `-dev` package |

Both protocols work because the setup repo records its GitHub marketplaces as
`owner/repo` (its ADR 0006); Claude Code tries SSH first, then HTTPS.

## Sharing the Hugging Face cache between users

Models are big, so everyone on a server can share one hub cache while each user
keeps their own `HF_HOME` (token, login state). No group and no sudo: when the
`hf-cache` Step's directory is outside your home, it asks whether to share it
with every user of the server (or set `HF_HUB_CACHE_SHARED=yes`):

```bash
HF_HUB_CACHE_DIR=/shared/huggingface_cache/hub HF_HUB_CACHE_SHARED=yes ./init.sh run hf-cache
```

Sharing runs `admin/share-hf-cache.sh` as you: every user may read, add and
replace entries, and a default ACL keeps new entries that way whoever creates
them, whatever their umask (Hugging Face's `blobs/` stay read-only, as it makes
them). Other users get it by pointing their own `HF_HUB_CACHE` there (the
`hf-cache` Step offers it once it is exported system-wide). Adding a user takes
nothing.

Making it every user's default, including users who don't run this Pipeline,
needs root: tick the optional `hf-export` Step in the checklist, or run
`./init.sh run hf-export`. It prints the sudo command, and takes the terminal
when sudo needs your password (with passwordless sudo it runs without one).
Never run `init.sh` itself with sudo: it would set up root's account instead of
yours, so outside a container or CI job it refuses. The same root run also opens any parent
folder others can't enter and installs `acl` when `setfacl` is missing. Without
the Pipeline, root runs the script directly, no clone needed:

```bash
curl -fsSL https://raw.githubusercontent.com/scott306lr/my-init-pipeline/main/admin/share-hf-cache.sh \
  | sudo bash -s -- /shared/huggingface_cache/hub
```

Any user can then change any cached file, including model code that
`trust_remote_code` runs, so share only on a server whose users you trust.

## Known caveats

- herdr always adds a SessionStart hook with this machine's absolute path to
  `~/.claude/settings.json`, which is shared. The `herdr` Step rewrites it to the
  `$HOME` form, and its Check flags it if it comes back. Updates to herdr's hook
  *script* (`dotfiles/hooks/herdr-agent-state.sh`) do land in the setup repo;
  sync them.
- `install.sh` in the claude setup repo exits 0 even when a plugin marketplace
  fails to register. `claude-config` surfaces those warnings as a Note.

## Tests

```bash
tests/run.sh                              # bats: runner behaviour with fake Actions (fetches bats-core on first use)
tests/e2e.sh                              # real installs in a throwaway HOME, run twice; the second must be a no-op
GH_TOKEN=$(gh auth token) tests/e2e.sh    # also covers claude-config and herdr
tests/docker.sh                           # ubuntu:22.04, non-root, no SSH key (HTTPS only), twice
tests/docker.sh --interactive             # shell in that container, to try gh auth login by hand
tests/admin.sh                            # sharing as root (in ubuntu:22.04; in CI, on the runner): the script, and the hf-cache Step as a user
```

CI (`.github/workflows/ci.yml`, ubuntu-22.04) runs shellcheck, bats, a bootstrap
dry run, the admin test and the non-interactive e2e.

The checklist is [gum](https://github.com/charmbracelet/gum) `choose`, pinned and
checksum-verified, fetched on first use into `~/.local/state/my-init-pipeline/bin`
(it is the runner's helper, not a Tool on your PATH). Space ticks and unticks, `a`
ticks all, Enter runs. If gum can't be fetched, the Run warns and runs every Step.

Design decisions: [docs/adr/](docs/adr/).
