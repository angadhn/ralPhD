# Human Review Needed — Phase 2 → Phase 3 Gate

## What was completed

**Phase 1** — Fixed `PROJECT_ROOT` derivation in `init-project.sh`:
- `PROJECT_ROOT` now derived from WORKSPACE argument (not cwd)
- Dangling symlink detection fixed (`[ -L ] || [ ! -e ]` pattern)
- Test 15d added: verifies Quick Start B creates dirs inside workspace

**Phase 2** — Symlinked `.claude/agents` in local mode:
- `init-project.sh` now symlinks `$WORKSPACE/.claude/agents` → `$RALPH_HOME/.claude/agents` (matching `specs/` and `templates/` pattern)
- `ralphd` launcher now self-heals `.claude/agents` symlink alongside `specs/templates`
- 160/161 tests pass (1 pre-existing failure in tools/__init__.py unrelated to this work)

## What Phase 3 will do

**Fix `ralphd` launcher cwd and self-healing** (`init-project.sh`):
- Add `cd "$SCRIPT_DIR"` to the embedded `ralphd` launcher before `exec ralph-loop.sh`, so all relative paths in `ralph-loop.sh` resolve against the workspace directory
- Remove the `basename = .ralph` guard from content symlink self-healing so it works for any workspace directory name (not just `.ralph`)

This is a safe change: the launcher already sets `SCRIPT_DIR` to its own directory; `cd` just ensures cwd matches. Removing the basename guard generalizes healing to Quick Start B workspaces.

## Files modified so far

- `scripts/init-project.sh` — PROJECT_ROOT derivation + .claude/agents symlink + launcher self-healing
- `tests/test-workflow-local.sh` — test 15d (Quick Start B path verification)
- `checkpoint.md`, `implementation-plan.md` — updated state
