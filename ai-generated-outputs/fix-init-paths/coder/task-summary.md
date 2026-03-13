# Task Summary — Fix ralphd launcher cwd and self-healing

**Task:** 3. Fix launcher cwd + self-healing
**Thread:** fix-init-paths
**Date:** 2026-03-13

## What was changed

### `scripts/init-project.sh` (embedded ralphd launcher heredoc)

**Change 1 (line 239):** Added `cd "$SCRIPT_DIR"` before `exec "$RALPH_HOME/ralph-loop.sh" "$@"`
- Ensures all relative paths in ralph-loop.sh (checkpoint.md, implementation-plan.md, logs/, etc.) resolve against the workspace directory regardless of where the user invoked `./ralphd`

**Change 2 (line 221):** Removed `&& [ "$(basename "$SCRIPT_DIR")" = ".ralph" ]` guard from content symlink self-healing condition
- Before: `if [ "$SCRIPT_DIR" != "$PARENT_DIR" ] && [ "$(basename "$SCRIPT_DIR")" = ".ralph" ]; then`
- After: `if [ "$SCRIPT_DIR" != "$PARENT_DIR" ]; then`
- Self-healing now works for any workspace directory name, not just `.ralph`

## Why

1. `ralphd` previously ran `ralph-loop.sh` without changing cwd, so relative paths like `checkpoint.md` resolved against wherever the user invoked `./ralphd` from — not the workspace.
2. The `basename = .ralph` guard prevented self-healing for users who use custom workspace directory names (e.g., `.framework`, `.workspace`, etc.) in split layout.

## Test results

160/161 tests passed. The 1 failing test (`tools/__init__.py: all 22 tools load`) is pre-existing and unrelated to this task.
