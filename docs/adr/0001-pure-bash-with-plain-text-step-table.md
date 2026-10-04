# Pure bash, with the Pipeline declared as a plain-text table

The Pipeline is declared in `pipeline.conf`, one whitespace-separated line per Step
(`step action requires...`), and the runner is plain bash. We considered JSON (the
first idea), YAML/TOML, a Python runner, and Ansible. The deciding constraint is
bootstrap: a fresh server reliably has bash, curl and git, but not `jq`, a YAML
parser, pip, or root to install them. Bash's `read` parses the table with no
dependencies, and the table stays readable at a glance.

## Consequences

- No nested data: an Action takes no per-Step arguments (shared logic goes in `lib/`).
- If the runner outgrows bash, the table format is trivial to read from any language.
