# tmux-wtree

A tmux plugin that automates the git-worktree-per-task workflow for parallel
development. Create a worktree, get a pane for it, and clean up when branches
merge — all through tmux keybindings, no separate CLI required.

Designed for running multiple Claude Code sessions (or any parallel workloads)
side by side without serialising work across branches.

## How it works

- **Session = repo.** Each repo gets its own tmux session.
- **Pane = worktree.** Tasks tile in a 2-column grid so multiple in-flight
  branches are visible simultaneously.
- **Cleanup is automatic.** Every new worktree creation first sweeps merged
  branches — no cron job or git hook needed.

```
┌─────────────────┬─────────────────┐
│  feature/auth   │  fix/typo-crash │
│  [slot 0]       │  [slot 1]       │
├─────────────────┼─────────────────┤
│  refactor/db    │  chore/deps     │
│  [slot 2]       │  [slot 3]       │
└─────────────────┴─────────────────┘
```

## Requirements

| Tool | Required | Purpose |
|------|----------|---------|
| `tmux` 3.2+ | yes | panes, sessions, `display-popup` |
| `git` (with worktree support) | yes | worktree create/remove |
| `jq` | yes | parsing JSON output |
| `gh` | optional | accurate merge detection (catches squash-merges) |
| `fzf` | optional | interactive picker in the list popup |

Missing `gh` degrades to `git branch --merged` (a warning is shown once).
Missing `fzf` makes the list popup read-only.

## Installation

### TPM (recommended)

Add to `~/.tmux.conf`:

```tmux
set -g @plugin 'sameera207/tmux-wtree'
```

Then press `prefix + I` to install.

### Manual

```bash
git clone https://github.com/sameera207/tmux-wtree ~/.tmux/plugins/tmux-wtree
echo "run-shell ~/.tmux/plugins/tmux-wtree/wtree.tmux" >> ~/.tmux.conf
tmux source ~/.tmux.conf
```

## Usage

| Keybinding | Action |
|------------|--------|
| `prefix + W` | Prompt for a branch name, create a worktree and a grid pane |
| `prefix + L` | Open a popup listing all worktrees for this session |

Scripts can also be run directly:

```bash
scripts/new-worktree.sh <branch>
scripts/clean.sh
scripts/list.sh
```

### Creating a worktree

Press `prefix + W`, type a branch name, and hit Enter. If the branch doesn't
exist it is created. The new pane opens in the worktree directory without
stealing focus from your current pane.

### Listing worktrees

Press `prefix + L` to open a popup showing all tool-managed panes:

```
SLOT    BRANCH                         PANE          STATUS
─────────────────────────────────────────────────────────────
0       feature/auth                   %3            active
1       fix/typo-crash                 %4            active
2       refactor/db                    %5            merged — pending cleanup
```

With `fzf` installed, selecting a row jumps directly to that pane.

### Cleanup

Merged worktrees are removed automatically at the start of every
`new-worktree.sh` run. You can also trigger cleanup manually:

```bash
scripts/clean.sh
```

For each merged worktree, cleanup:
1. Kills the tmux pane
2. Removes the git worktree
3. Force-deletes the local branch
4. Renumbers remaining pane slots to close any gaps

## Configuration

Set options in `~/.tmux.conf` before the `run-shell` / TPM line:

```tmux
set -g @wtree-key     'W'                      # keybinding for new worktree
set -g @wtree-list-key 'L'                     # keybinding for list popup
set -g @wtree-dir     '../#{repo}-#{branch}'   # worktree location template
```

### `@wtree-dir` template variables

| Variable | Expands to |
|----------|------------|
| `#{repo}` | Repository directory name |
| `#{branch}` | Branch name with `/` replaced by `-` |

The default `../#{repo}-#{branch}` places worktrees as siblings of the main
repo: `../myrepo-feature-auth`, `../myrepo-fix-crash`, etc.

## Pane grid details

Panes fill left-to-right, top-to-bottom in a strict 2-column layout:

- **Even slots** (0, 2, 4 …): full-width row added at the bottom of the window
- **Odd slots** (1, 3, 5 …): horizontal split to the right of the preceding even pane

Manual splits (`prefix + %` / `prefix + "`) are completely independent —
they are ignored by the placement algorithm and never disturb the grid.
Tool-managed panes are identified by the tmux user options `@wtree_slot` and
`@wtree_branch` set on each pane.

## Repo structure

```
tmux-wtree/
├── wtree.tmux              # TPM entrypoint: dependency check + keybindings
├── scripts/
│   ├── new-worktree.sh     # prefix+W handler
│   ├── clean.sh            # merge detection + removal + renumbering
│   ├── list.sh             # prefix+L popup
│   └── lib/
│       ├── grid.sh         # pane placement and tagging
│       └── merge-check.sh  # gh / git merge status abstraction
└── LICENSE
```

## License

MIT
