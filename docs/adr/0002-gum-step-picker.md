# A gum checklist picks the Steps, the way create-t3-app prompts

`./init.sh run` on a terminal, with no Step named, first shows a checklist of
every Step and runs the ticked ones (plus what they require). This follows
create-t3-app: prompt by default, `-y` to take the defaults, and no prompt
without a terminal. The defaults are the Steps with work to do, so Enter does
what a plain Run did before. A ticked Step whose Check passes is re-run, the
one way the checklist does more than the defaults.

create-t3-app builds its prompts with `@clack/prompts`, which needs Node, and
ADR 0001 allows nothing a fresh server lacks. We use charmbracelet/gum's
`choose --no-limit` instead: a static binary for x86_64 and arm64 with published
checksums. The runner fetches a pinned version on first use into its state
directory. We rejected:

- fzf `--multi`: a Step of this Pipeline, so it is missing on the first Run.
- whiptail `--checklist`: not on minimal images (e.g. the ubuntu:22.04 image).
- bash `select`: one choice at a time.

## Consequences

- The first Run on a terminal downloads gum (about 5 MB). If it can't be
  fetched, the Run warns and runs every Step, so no Run is blocked on it.
- No picker for `--dry-run` (it must not download anything) or `--upgrade`.
- gum splits `--selected` on commas, so Step labels have their commas replaced.
