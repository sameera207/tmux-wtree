#!/usr/bin/env bash
# Popup content: lists open worktrees with slot, branch, pane ID, and status.
# With fzf: selecting a row jumps to that pane and closes the popup.
# Without fzf: read-only display, press q to close.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/merge-check.sh
source "$SCRIPT_DIR/lib/merge-check.sh"

pane_path="${1:-$PWD}"
repo_root=$(git -C "$pane_path" rev-parse --show-toplevel 2>/dev/null)
main_branch=$(git -C "$repo_root" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
  | sed 's|refs/remotes/origin/||')
[[ -z "$main_branch" ]] && main_branch="main"

header=$(printf "%-6s  %-28s  %-12s  %s" "SLOT" "BRANCH" "PANE" "STATUS")
divider=$(printf '%0.s─' $(seq 1 65))

rows=()
pane_ids=()

while IFS=' ' read -r pane_id slot branch; do
  [[ -z "$slot" || -z "$branch" ]] && continue

  if is_merged "$branch" "$repo_root" "$main_branch" 2>/dev/null; then
    status="merged — pending cleanup"
  else
    status="active"
  fi

  rows+=("$(printf "%-6s  %-28s  %-12s  %s" "$slot" "$branch" "$pane_id" "$status")")
  pane_ids+=("$pane_id")
done < <(tmux list-panes -s -F '#{pane_id} #{@wtree_slot} #{@wtree_branch}' 2>/dev/null \
  | awk '$2 ~ /^[0-9]+$/ && $3 != "" { print }' | sort -k2 -n)

if [[ ${#rows[@]} -eq 0 ]]; then
  echo "No wtree-managed panes found in this session."
  echo ""
  echo "Press any key to close..."
  read -r -n 1
  exit 0
fi

if command -v fzf &>/dev/null; then
  selected=$(printf '%s\n' "${rows[@]}" \
    | fzf --no-info --reverse \
          --header="$header"$'\n'"$divider" \
          --prompt="Jump to: ")
  if [[ -n "$selected" ]]; then
    # Pane ID is the 3rd space-delimited field.
    target_pane=$(echo "$selected" | awk '{print $3}')
    tmux select-pane -t "$target_pane"
  fi
else
  echo "$header"
  echo "$divider"
  for row in "${rows[@]}"; do
    echo "$row"
  done
  echo ""
  echo "Press q to close"
  while read -r -n 1 key; do
    [[ "$key" == "q" || "$key" == "Q" ]] && break
  done
fi
