#!/usr/bin/env bash
# Pane placement and tagging for the wtree 2-column grid.
#
# Slot layout (0-indexed):
#   0 | 1
#   2 | 3
#   4 | 5
#   ...
#
# Even slots = left column (full-width -fv split at bottom of window).
# Odd slots  = right column (horizontal split from the left-column peer).

# Returns the next slot index for this session.
wtree_next_slot() {
  local max
  max=$(tmux list-panes -s -F '#{@wtree_slot}' 2>/dev/null \
    | grep -E '^[0-9]+$' | sort -n | tail -1)
  [[ -z "$max" ]] && echo 0 || echo $((max + 1))
}

# Returns the pane_id for a given slot in this session.
wtree_pane_by_slot() {
  local slot="$1"
  tmux list-panes -s -F '#{pane_id} #{@wtree_slot}' 2>/dev/null \
    | awk -v s="$slot" '$2 == s { print $1; exit }'
}

# Creates a new pane for the given slot and returns its pane_id.
# Does NOT switch focus to the new pane (-d flag).
wtree_create_pane() {
  local slot="$1"
  local new_pane

  if (( slot % 2 == 0 )); then
    # Even slot: new full-width row at the bottom of the window.
    if (( slot == 0 )); then
      new_pane=$(tmux split-window -fv -d -P -F '#{pane_id}')
    else
      local parent
      parent=$(wtree_pane_by_slot $((slot - 2)))
      new_pane=$(tmux split-window -fv -d -P -F '#{pane_id}' -t "$parent")
    fi
  else
    # Odd slot: horizontal split to the right of the left-column peer.
    local left_peer
    left_peer=$(wtree_pane_by_slot $((slot - 1)))
    new_pane=$(tmux split-window -h -d -P -F '#{pane_id}' -t "$left_peer")
  fi

  echo "$new_pane"
}

# Pane border label for windows containing wtree panes: tagged panes show
# their branch name, everything else keeps tmux's normal index/title look.
WTREE_BORDER_FORMAT='#{?@wtree_branch,[worktree] #{@wtree_branch},#{?pane_active,#[reverse],}#{pane_index} "#{pane_title}"}'

# Tags a pane with its slot index and branch name, and turns on the
# branch-aware border label for the window it lives in. Scoped to that one
# window (set-window-option, not -g) so it doesn't affect other windows.
wtree_tag_pane() {
  local pane_id="$1" slot="$2" branch="$3"
  tmux set-option -p -t "$pane_id" @wtree_slot   "$slot"
  tmux set-option -p -t "$pane_id" @wtree_branch "$branch"

  local border_enabled
  border_enabled=$(tmux show-option -gv @wtree-border 2>/dev/null)
  if [[ "$border_enabled" != "off" ]]; then
    local win
    win=$(tmux display-message -p -t "$pane_id" '#{window_id}')
    tmux set-window-option -t "$win" pane-border-status top
    tmux set-window-option -t "$win" pane-border-format "$WTREE_BORDER_FORMAT"
  fi
}

# Reassigns contiguous slot numbers (0, 1, 2, …) to all tagged panes,
# preserving their existing relative order.
wtree_renumber() {
  local i=0 pane_id
  while IFS=' ' read -r pane_id _slot; do
    tmux set-option -p -t "$pane_id" @wtree_slot "$i"
    (( i++ ))
  done < <(tmux list-panes -s -F '#{pane_id} #{@wtree_slot}' 2>/dev/null \
    | awk '$2 ~ /^[0-9]+$/ { print }' | sort -k2 -n)
}
