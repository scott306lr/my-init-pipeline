# Glossary

**Pipeline** — The full, declared set of Steps that brings a fresh server to the desired state, together with the dependencies between them.

**Step** — A named node in the Pipeline. It is identified by its name, which stays stable; it is bound to exactly one Action and lists the other Steps (by name) it requires. Dependencies are always expressed between Step names, never between Actions.
_Avoid_: service, app, stage.

**Action** — The unit of work a Step performs, such as installing a tool or applying configuration. The Action bound to a Step may be replaced without changing the Step's name or its dependencies.

**Requires** — The relation "Step A cannot start until Step B has succeeded". Steps with no unmet Requires between them may run at the same time.

**Check** — The test that tells whether a Step's outcome already holds on this server. A Step whose Check passes is skipped, unless it is forced.

**Run** — One execution of the Pipeline, or a selected part of it, on one server.

**Interactive Step** — A Step that needs a human at the keyboard, for example to log in. A non-interactive Run skips it.

**Note** — A message a Step leaves for the human, shown at the end of a Run. It covers follow-up work the Pipeline does not do itself, such as logging in to a Tool.

**Tool** — A program the Pipeline puts on the server (claude, codex, herdr, gh, nvitop). It is installed by a Step, but it is not itself a Step.
