# Step picker: the checklist `./init.sh run` shows on a terminal (ADR 0002).
# Sourced by init.sh after lib/pipeline.sh.

GUM_VERSION=2.0.2

# gum_bin — path to a pinned gum, fetched on first use (checksum verified) into
# the state dir, so it is a helper of the runner, not a Tool on PATH.
# MIP_GUM overrides it (tests).
gum_bin() {
  local dir="$MIP_STATE_DIR/bin" arch file base sha
  if [ -n "${MIP_GUM:-}" ]; then printf '%s\n' "$MIP_GUM"; return; fi
  if [ ! -x "$dir/gum" ] || [ "$("$dir/gum" --version 2>/dev/null)" != "gum version v$GUM_VERSION" ]; then
    case "$(uname -m)" in
      x86_64 | amd64) arch=x86_64 ;;
      aarch64 | arm64) arch=arm64 ;;
      *) return 1 ;;
    esac
    printf 'Fetching gum v%s for the Step picker...\n' "$GUM_VERSION" >&2
    file="gum_${GUM_VERSION}_Linux_$arch.tar.gz"
    base="https://github.com/charmbracelet/gum/releases/download/v$GUM_VERSION"
    sha="$(release_sha256 "$base/checksums.txt" "$file")" && [ -n "$sha" ] || return 1
    install_release_binary "$base/$file" gum "$sha" "$dir" >/dev/null || return 1
  fi
  printf '%s\n' "$dir/gum"
}

# pick_steps — show every Step with its summary and Check result; print the
# ticked Step names. Steps with work to do start ticked, so Enter runs what a
# Run without the picker would; ticking a done Step upgrades it. Exit status: 130 when cancelled, other non-zero
# when no picker could be shown.
pick_steps() {
  local gum s st mark label
  local -a opts=() ticked=()
  gum="$(gum_bin)" || return 1
  printf 'Checking %d Steps...\n' "${#STEPS[@]}" >&2
  for s in "${STEPS[@]}"; do
    st="$(check_status "$s")"
    case "$st" in done | na) mark="$st" ;; *) mark="" ;; esac
    # gum splits --selected on commas, so labels carry none.
    label="$(printf '%-15s %-4s  %s' "$s" "$mark" "$(action_field "$s" summary | tr ',' ';' | cut -c 1-72)")"
    opts+=("$label"$'\t'"$s")
    if [ "$st" = todo ]; then ticked+=("$label"); fi
  done
  "$gum" choose --no-limit --label-delimiter $'\t' --height "$((${#STEPS[@]} + 1))" \
    --header "Steps to run (ticked = install; a ticked 'done' Step is upgraded)" \
    --selected "$(IFS=,; printf '%s' "${ticked[*]}")" "${opts[@]}"
}
