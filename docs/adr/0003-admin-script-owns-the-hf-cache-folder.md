# The admin script owns the Cache folder's rules

`admin/share-hf-cache.sh` is the single owner of what a Cache folder is: its
layout (`hub/` and `datasets/`), which paths are valid, and whether it is
Shared or Exported. The hf-cache and hf-export Actions ask it through its
command line and hold none of those rules themselves.

ADR 0001 says shared logic goes in `lib/`. This is the exception, because the
admin script must work alone: an admin who does not run the Pipeline pipes it
into `sudo bash`, so it can source nothing. Any rule kept in `lib/` would need
a second copy in the script, and those copies drifted (f541dce fixed two such
bugs; a third, a trailing `/` in `HF_CACHE_DIR`, was found after it). We
considered an HF-only file under `lib/` and rejected it for that reason.
Single-file install scripts are the convention for this use (docker-install,
rustup-init.sh).

## Consequences

- The Actions pay a subprocess per question. One state query answers several
  at once.
- Which Cache folder is in effect for a user stays on the Pipeline side
  (`lib/`), because it reads that user's settings and env file, which the
  script, run as root, cannot see.
- Moving a user's downloads into a Cache folder stays in the hf-cache Action:
  a standalone admin never needs it.
- The script's query flags are the Pipeline's own interface and may change;
  `share-hf-cache.sh DIR` is the documented use and stays.
