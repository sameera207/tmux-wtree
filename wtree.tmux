#!/usr/bin/env bash
# TPM entrypoint for tmux-wtree.
# Checks required dependencies, then registers keybindings.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Dependency check --------------------------------------------------------
missing=()
for dep in tmux git jq; do
  command -v "$dep" &>/dev/null || missing+=("$dep")
done
if [[ ${#missing[@]} -gt 0 ]]; then
  tmux display-message "wtree: missing required dependencies: ${missing[*]}"
  exit 0
fi

# --- Read config with defaults -----------------------------------------------
wtree_key=$(tmux show-option -gv @wtree-key 2>/dev/null)
[[ -z "$wtree_key" ]] && wtree_key='W'

wtree_list_key=$(tmux show-option -gv @wtree-list-key 2>/dev/null)
[[ -z "$wtree_list_key" ]] && wtree_list_key='L'

# --- Register keybindings ----------------------------------------------------
# Neither run-shell's -c nor display-popup's default start-directory reliably
# track the triggering pane, so the path is passed explicitly as an argument:
# #{pane_current_path} is expanded against the pane where the key was pressed
# when tmux parses the bound command line itself, before run-shell/display-popup
# ever run.

# prefix + W  →  prompt for branch name, then create worktree + pane
tmux bind-key "$wtree_key" \
  command-prompt -p "New worktree branch:" \
  "run-shell '$CURRENT_DIR/scripts/new-worktree.sh \"%%\" \"#{pane_current_path}\"'"

# prefix + L  →  popup listing open worktrees for this session
tmux bind-key "$wtree_list_key" \
  display-popup -E -w 60% -h 40% "$CURRENT_DIR/scripts/list.sh '#{pane_current_path}'"
