# my-init-pipeline

One command to bring a fresh Linux server to my working setup, **without root**:
gh, Claude Code (plus my synced `~/.claude`), Codex, uv, nvitop, zoxide and herdr.

```bash
curl -fsSL https://raw.githubusercontent.com/scott306lr/my-init-pipeline/main/bootstrap.sh | bash
```

This clones the repo to `~/my-init-pipeline` and runs `./init.sh run`. Safe to re-run:
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
zoxide          zoxide-install   path-env
herdr           herdr-install    claude-config codex
```

Dependencies decide the order; Steps with no dependency between them run in parallel.
Interactive Steps (like `gh-auth`) take the terminal while background Steps keep
going; anything that requires them waits.

## Commands

| Command | |
|---|---|
| `./init.sh run` | Run the whole Pipeline |
| `./init.sh run herdr` | Run `herdr` plus whatever it requires that isn't satisfied yet |
| `./init.sh run --force codex` | Re-run a Step even though its Check passes |
| `./init.sh run --upgrade` | Update every installed Tool with its own updater |
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
   # notes:   Anything a future you needs to know (shown by `describe`)

   check()   { have mytool; }          # 0 = satisfied, 2 = not applicable here, else = to do
   run()     { run_installer https://example.com/install.sh; }
   upgrade() { mytool self-update; }   # optional, used by --upgrade
   note()    { echo "Remember to ..."; }  # optional, shown after a Run where it ran
   ```

2. Add a line to `pipeline.conf`: `mytool  mytool-install  path-env`.
3. `./init.sh describe mytool`, then `./init.sh run mytool`.

Rules for Actions:
- **Checks must have no side effects.** `list` and `--dry-run` call them.
- After `run`, the runner runs the Check again, and the Step only succeeds if it passes.
- Never edit rc files. Use `add_path '$HOME/some/bin'` for PATH and
  `add_shell_init '<line>'` for interactive-only setup (e.g. `eval "$(tool init bash)"`).
  Both record into `~/.config/my-init-pipeline/env.sh`. `~/.bashrc` sources that file through one
  marked block.
- Each function runs in a fresh `bash -eo pipefail`, with `lib/common.sh` and `config.sh`
  loaded. Helpers: `have`, `info`, `die`, `fetch`, `run_installer`,
  `github_latest_tag`, `add_path`, `add_shell_init`.

To swap how something is installed, point its Step at a different Action. The
Step name and every dependency on it stay unchanged. To remove a Step, delete its
line; validation reports anything that still requires it.

## Settings

`config.sh` holds the settings for `claude-config`. Each one can also be overridden from the environment:

| Variable | Default | |
|---|---|---|
| `CLAUDE_SETUP_REPO` | `scott306lr/my-claude-setup` | the private copy of [my-portable-claude](https://github.com/scott306lr/my-portable-claude) |
| `CLAUDE_SETUP_DIR` | `~/my-claude-setup` | where it is cloned |
| `CLAUDE_SETUP_PROTOCOL` | `https` | `https` (via gh's credential helper) or `ssh` (needs a key on GitHub) |
| `CLAUDE_SETUP_REF` | *(default branch)* | branch for a fresh clone, e.g. to test a change before merging it |

Both protocols work because the setup repo records its GitHub marketplaces as
`owner/repo` (its ADR 0006); Claude Code tries SSH first, then HTTPS.

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
```

CI (`.github/workflows/ci.yml`, ubuntu-22.04) runs shellcheck, bats, a bootstrap
dry run and the non-interactive e2e.

Design decisions: [docs/adr/](docs/adr/).
