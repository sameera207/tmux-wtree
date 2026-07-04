#!/usr/bin/env bash
# Returns 0 if branch is merged, 1 if not.
# Usage: is_merged <branch> <repo-root> [<base-branch>]
is_merged() {
  local branch="$1"
  local repo_root="$2"
  local base="${3:-main}"

  if command -v gh &>/dev/null; then
    local state
    state=$(cd "$repo_root" && gh pr view "$branch" --json state -q .state 2>/dev/null)
    [[ "$state" == "MERGED" ]]
  else
    # Warn once per session that squash-merge detection is unavailable
    local warned
    warned=$(tmux show-option -gv @wtree_warned_no_gh 2>/dev/null)
    if [[ "$warned" != "1" ]]; then
      tmux display-message "wtree: gh not found — using git branch --merged (squash-merges not detected)"
      tmux set-option -g @wtree_warned_no_gh "1"
    fi
    git -C "$repo_root" branch --merged "$base" 2>/dev/null | sed 's/^[* ]*//' | grep -qxF "$branch"
  fi
}
