# The checklist `./init.sh run` shows on a terminal to choose Steps (ADR 0002).
# Sourced by init.sh; uses lib/pipeline.sh's Step list and lib/action.sh's
# descriptor (check_status, is_optional, action_field).

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
    printf 'Fetching gum v%s for the checklist...\n' "$GUM_VERSION" >&2
    file="gum_${GUM_VERSION}_Linux_$arch.tar.gz"
    base="https://github.com/charmbracelet/gum/releases/download/v$GUM_VERSION"
    sha="$(release_sha256 "$base/checksums.txt" "$file")" && [ -n "$sha" ] || return 1
    install_release_binary "$base/$file" gum "$sha" "$dir" >/dev/null || return 1
    # Earlier pins (bin/gum-<ver>/, and v2.0.2's bin/gum) are dead weight now.
    find "$MIP_STATE_DIR/bin" -mindepth 1 -maxdepth 1 \( -name gum -o -name 'gum-*' \) ! -name "gum-$GUM_VERSION" -exec rm -rf {} +
  fi
  printf '%s\n' "$dir/gum"
}

# checklist — show every Step with its summary and Check result; print each
# ticked Step as "NAME CHECK", its Check result as shown (done | na | todo). Steps with work to do start ticked, except optional ones
# (marked "opt"), so Enter runs what a Run without the checklist would; ticking an
# optional Step runs it, ticking a done Step upgrades it. Exit status: 130 when cancelled, other non-zero
# when no checklist could be shown.
checklist() {
  local gum s st mark label picked
  local -a opts=() ticked=()
  local -A status=()
  gum="$(gum_bin)" || return 1
  printf 'Checking %d Steps...\n' "${#STEPS[@]}" >&2
  for s in "${STEPS[@]}"; do
    st="$(check_status "$s")"
    status[$s]="$st"
    case "$st" in done | na) mark="$st" ;; *) mark="" ;; esac
    if [ "$st" = todo ] && is_optional "$s"; then mark=opt; fi
    # gum splits --selected on commas, so labels carry none.
    label="$(printf '%-15s %-4s  %s' "$s" "$mark" "$(action_field "$s" summary | tr ',' ';' | cut -c 1-72)")"
    opts+=("$label"$'\t'"$s")
    if [ "$st" = todo ] && [ "$mark" != opt ]; then ticked+=("$label"); fi
  done
  picked="$("$gum" choose --no-limit --no-show-help --label-delimiter $'\t' --height "$((${#STEPS[@]} + 1))" \
    --header "$(printf '%s\n' "Steps to run: ticked ones install; 'opt' = optional, off unless ticked; a ticked 'done' Step is upgraded" \
      "space: tick/untick   a: all   enter: run   ctrl+c: cancel")" \
    --selected "$(IFS=,; printf '%s' "${ticked[*]}")" "${opts[@]}")" || return
  while read -r s; do
    if [ -n "$s" ]; then printf '%s %s\n' "$s" "${status[$s]:-todo}"; fi
  done <<<"$picked"
}
