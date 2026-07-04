#!/usr/bin/env bash
# Creates a git worktree and a tagged tmux pane for it in the 2-column grid.
# Usage: new-worktree.sh <branch-name>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/grid.sh
source "$SCRIPT_DIR/lib/grid.sh"

branch="${1:-}"
if [[ -z "$branch" ]]; then
  tmux display-message "wtree: branch name required"
  exit 1
fi

# Run cleanup pass before adding new worktree.
"$SCRIPT_DIR/clean.sh"

repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
if [[ -z "$repo_root" ]]; then
  tmux display-message "wtree: not inside a git repository"
  exit 1
fi

repo_name=$(basename "$repo_root")
safe_branch="${branch//\//-}"

# Resolve worktree directory from config template.
dir_template=$(tmux show-option -gv @wtree-dir 2>/dev/null)
[[ -z "$dir_template" ]] && dir_template='../#{repo}-#{branch}'

worktree_rel="${dir_template//\#\{repo\}/$repo_name}"
worktree_rel="${worktree_rel//\#\{branch\}/$safe_branch}"

# Compute absolute path without requiring the path to exist yet.
if [[ "$worktree_rel" == /* ]]; then
  worktree_abs="$worktree_rel"
else
  worktree_abs=$(python3 -c \
    "import os; print(os.path.normpath(os.path.join('$repo_root', '$worktree_rel')))")
fi

# Create the git worktree (create branch if it doesn't exist).
if git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch"; then
  worktree_output=$(git -C "$repo_root" worktree add "$worktree_abs" "$branch" 2>&1)
else
  worktree_output=$(git -C "$repo_root" worktree add -b "$branch" "$worktree_abs" 2>&1)
fi
if [[ $? -ne 0 ]]; then
  tmux display-message "wtree: $worktree_output"
  exit 1
fi

# Create the pane and tag it.
slot=$(wtree_next_slot)
pane_id=$(wtree_create_pane "$slot")
wtree_tag_pane "$pane_id" "$slot" "$branch"

# Start the shell in the worktree directory.
tmux send-keys -t "$pane_id" "cd '$worktree_abs' && clear" Enter
