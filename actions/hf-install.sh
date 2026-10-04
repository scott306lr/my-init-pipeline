# summary: Install the Hugging Face CLI (`hf download`, `hf upload`, `hf auth login`) as a uv tool
# check:   hf is on PATH
# notes:   `uv tool install huggingface_hub` (the hf entry point ships in the base
#          package). Log in per machine with `hf auth login` if you need gated or
#          private repos.

check() { have hf; }

run() {
  uv tool install huggingface_hub
  hf version
}

upgrade() { uv tool upgrade huggingface_hub; }

note() { echo "Hugging Face: run 'hf auth login' for gated or private models."; }
