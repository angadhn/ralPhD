# Human Review Needed

**Thread:** fix-init-paths
**Date:** 2026-03-13
**Completed phase:** Phase 1 — Fix PROJECT_ROOT derivation

## What was completed

**Phase 1: Fix PROJECT_ROOT derivation in `scripts/init-project.sh`**

- `PROJECT_ROOT` now derives from WORKSPACE using a basename heuristic:
  - WORKSPACE ends in `.ralph` → PROJECT_ROOT = parent directory (split layout)
  - Otherwise → PROJECT_ROOT = WORKSPACE (all-in-one layout, Quick Start B)
- Dangling symlink detection fixed: `[ -L link ] || [ ! -e link ]` + `rm -f` prevents `set -e` exit on broken symlinks
- Test 15d added: verifies Quick Start B puts content dirs in WORKSPACE, not in cwd

All 160 previously-passing tests continue to pass (1 pre-existing failure unrelated to this change).

## What Phase 2 will do

**Phase 2: Symlink `.claude/agents/` in local mode**

Currently `init-project.sh` creates an empty `$WORKSPACE/.claude/agents/` directory in local mode. Phase 2 will:
1. Replace `mkdir -p "$WORKSPACE/.claude/agents"` with a symlink to `$RALPH_HOME/.claude/agents` (same pattern as `specs/` and `templates/`)
2. Add self-healing for `.claude/agents` in the embedded `ralphd` launcher alongside the existing specs/templates healing

This means new local workspaces will automatically see all framework agents via the symlink, without needing to copy them.

**Files that will be changed:** `scripts/init-project.sh` only (the local-mode `.claude/agents` block and the embedded ralphd launcher template)
