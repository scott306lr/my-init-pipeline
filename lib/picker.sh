# Step picker: the checklist `./init.sh run` shows on a terminal (ADR 0002).
# Sourced by init.sh after lib/pipeline.sh.

# v0.17.0, not v2: gum v2's choose binds toggle to " ", but Bubble Tea v2 names
# that key "space", so space never toggles there (ADR 0002).
GUM_VERSION=0.17.0

# gum_bin — path to a pinned gum, fetched on first use (checksum verified) into
# a per-version folder of the state dir, so it is a helper of the runner, not a
# Tool on PATH. MIP_GUM overrides it (tests).
gum_bin() {
  local dir="$MIP_STATE_DIR/bin/gum-$GUM_VERSION" arch file base sha
  if [ -n "${MIP_GUM:-}" ]; then printf '%s\n' "$MIP_GUM"; return; fi
  if [ ! -x "$dir/gum" ]; then
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
# ticked Step names. Steps with work to do start ticked, except optional ones
# (marked "opt"), so Enter runs what a Run without the picker would; ticking an
# optional Step runs it, ticking a done Step upgrades it. Exit status: 130 when cancelled, other non-zero
# when no picker could be shown.
pick_steps() {
  local gum s st mark label
  local -a opts=() ticked=()
  gum="$(gum_bin)" || return 1
  printf 'Checking %d Steps...\n' "${#STEPS[@]}" >&2
  for s in "${STEPS[@]}"; do
    st="$(check_status "$s")"
    case "$st" in done | na) mark="$st" ;; *) mark="" ;; esac
    if [ "$st" = todo ] && is_optional "$s"; then mark=opt; fi
    # gum splits --selected on commas, so labels carry none.
    label="$(printf '%-15s %-4s  %s' "$s" "$mark" "$(action_field "$s" summary | tr ',' ';' | cut -c 1-72)")"
    opts+=("$label"$'\t'"$s")
    if [ "$st" = todo ] && [ "$mark" != opt ]; then ticked+=("$label"); fi
  done
  "$gum" choose --no-limit --no-show-help --label-delimiter $'\t' --height "$((${#STEPS[@]} + 1))" \
    --header "$(printf '%s\n' "Steps to run: ticked ones install; 'opt' = optional, off unless ticked; a ticked 'done' Step is upgraded" \
      "space: tick/untick   a: all   enter: run   ctrl+c: cancel")" \
    --selected "$(IFS=,; printf '%s' "${ticked[*]}")" "${opts[@]}"
}
