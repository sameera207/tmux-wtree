#!/usr/bin/env bash
# Scans all worktrees for the current repo, removes any whose branch is merged,
# kills the associated tmux pane, deletes the local branch, and renumbers slots.
# Usage: clean.sh [repo-root]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/merge-check.sh
source "$SCRIPT_DIR/lib/merge-check.sh"
# shellcheck source=lib/grid.sh
source "$SCRIPT_DIR/lib/grid.sh"

if [[ -n "${1:-}" ]]; then
  repo_root="$1"
else
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
fi

main_branch=$(git -C "$repo_root" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
  | sed 's|refs/remotes/origin/||')
[[ -z "$main_branch" ]] && main_branch="main"

# Parse porcelain output into wt_path / wt_branch pairs.
wt_path=""
wt_branch=""
remove_list=()

process_entry() {
  [[ -z "$wt_path" || -z "$wt_branch" ]] && return
  [[ "$wt_path" == "$repo_root" ]] && return   # skip main worktree
  if is_merged "$wt_branch" "$repo_root" "$main_branch"; then
    remove_list+=("$wt_path" "$wt_branch")
  fi
}

while IFS= read -r line; do
  case "$line" in
    "worktree "*)
      process_entry
      wt_path="${line#worktree }"
      wt_branch=""
      ;;
    "branch refs/heads/"*)
      wt_branch="${line#branch refs/heads/}"
      ;;
  esac
done < <(git -C "$repo_root" worktree list --porcelain)
process_entry  # handle last entry

[[ ${#remove_list[@]} -eq 0 ]] && exit 0

i=0
while (( i < ${#remove_list[@]} )); do
  wt_path="${remove_list[$i]}"
  wt_branch="${remove_list[$((i+1))]}"
  (( i += 2 ))

  # Kill the tmux pane tagged with this branch (if any).
  pane_id=$(tmux list-panes -s -F '#{pane_id} #{@wtree_branch}' 2>/dev/null \
    | awk -v b="$wt_branch" '$2 == b { print $1; exit }')
  [[ -n "$pane_id" ]] && tmux kill-pane -t "$pane_id" 2>/dev/null || true

  # Remove worktree and local branch.
  git -C "$repo_root" worktree remove --force "$wt_path" 2>/dev/null || true
  git -C "$repo_root" branch -D "$wt_branch" 2>/dev/null || true
done

# Compact slot numbers so subsequent grid math stays correct.
wtree_renumber
