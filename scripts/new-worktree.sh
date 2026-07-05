#!/usr/bin/env bash
# Creates a git worktree and a tagged tmux pane for it in the 2-column grid.
# Usage: new-worktree.sh <branch-name> [pane-path] [origin-pane-id] [mode]
# mode is set internally ("--reuse" or "--force-recreate") when the
# conflict-resolution menu below re-invokes this script.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/grid.sh
source "$SCRIPT_DIR/lib/grid.sh"

branch="${1:-}"
if [[ -z "$branch" ]]; then
  tmux display-message "wtree: branch name required"
  exit 1
fi

# run-shell does not inherit the triggering pane's cwd, so the caller passes
# it explicitly (expanded from #{pane_current_path} in the bound command).
pane_path="${2:-$PWD}"
origin_pane="${3:-}"
mode="${4:-}"

repo_root=$(git -C "$pane_path" rev-parse --show-toplevel 2>/dev/null)
if [[ -z "$repo_root" ]]; then
  tmux display-message "wtree: not inside a git repository"
  exit 1
fi

# Run cleanup pass before adding new worktree.
"$SCRIPT_DIR/clean.sh" "$repo_root"

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

# Does a worktree already exist for this branch anywhere in the repo?
existing_wt_path=$(git -C "$repo_root" worktree list --porcelain \
  | awk -v b="refs/heads/$branch" '/^worktree /{p=$2} $0 == "branch "b {print p; exit}')

if [[ -n "$existing_wt_path" && -z "$mode" ]]; then
  # Ask whether to reuse it or wipe it and start fresh, rather than just
  # failing with git's raw "already exists" error.
  reuse_cmd="run-shell '\"$SCRIPT_DIR/new-worktree.sh\" \"$branch\" \"$pane_path\" \"$origin_pane\" --reuse'"
  recreate_cmd="run-shell '\"$SCRIPT_DIR/new-worktree.sh\" \"$branch\" \"$pane_path\" \"$origin_pane\" --force-recreate'"
  tmux display-menu -t "$origin_pane" -x C -y C \
    -T "wtree: '$branch' already has a worktree" \
    "Reuse existing worktree" r "$reuse_cmd" \
    "Remove it and recreate"  x "$recreate_cmd" \
    "Cancel" q ""
  exit 0
fi

if [[ "$mode" == "--force-recreate" && -n "$existing_wt_path" ]]; then
  stale_pane=$(tmux list-panes -a -F '#{pane_id} #{@wtree_branch}' 2>/dev/null \
    | awk -v b="$branch" '$2 == b { print $1; exit }')
  [[ -n "$stale_pane" ]] && tmux kill-pane -t "$stale_pane" 2>/dev/null
  git -C "$repo_root" worktree remove --force "$existing_wt_path" 2>/dev/null
  git -C "$repo_root" branch -D "$branch" 2>/dev/null
  existing_wt_path=""
fi

if [[ "$mode" == "--reuse" && -n "$existing_wt_path" ]]; then
  worktree_abs="$existing_wt_path"
else
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
fi

# Create the pane and tag it.
slot=$(wtree_next_slot)
pane_id=$(wtree_create_pane "$slot" "$origin_pane")
wtree_tag_pane "$pane_id" "$slot" "$branch"

# Start the shell in the worktree directory.
tmux send-keys -t "$pane_id" "cd '$worktree_abs' && clear" Enter
