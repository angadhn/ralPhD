# Checkpoint — Fix init-project path resolution and symlink fragility

**Thread:** fix-init-paths
**Last updated:** 2026-03-13
**Last agent:** plan
**Status:** planning complete

## Knowledge State

| Task | Status | Notes |
|------|--------|-------|
| 1. Fix PROJECT_ROOT derivation | done | Derive from WORKSPACE basename heuristic; dangling symlink fix; test 15d added |
| 2. Symlink .claude/agents | done | Symlinked to RALPH_HOME; self-healing added to ralphd launcher |
| 3. Fix launcher cwd + self-healing | done | Added `cd "$SCRIPT_DIR"` before exec; removed `basename=.ralph` guard |
| 4. Update docs | done | README Quick Start B + api-contract layout (Layout A/B) |
| 5. Test all quick-start paths | pending | New test cases for A, B, C paths |

## Last Reflection

Iter 15 (2026-03-13): Trajectory on track. Fresh thread start — plan is solid, 3-entry-point fix strategy is correct. No course correction needed. Proceeding with Phase 1 (PROJECT_ROOT derivation).
Iter 16 (2026-03-13): Phase 2 complete. .claude/agents now symlinked to RALPH_HOME in local mode; self-healing added to embedded ralphd launcher. 160/161 tests pass (pre-existing failure unrelated).
Iter 17 (2026-03-13): Phase 3 complete. ralphd launcher now cds to SCRIPT_DIR before exec; basename=.ralph guard removed from content symlink self-healing. 160/161 tests pass (same pre-existing failure).
Iter 18 (2026-03-13): Phase 4 complete. README Quick Start B updated to clarify content dirs go into workspace (not cwd). api-contract.md split into Layout A (all-in-one, QS-B) and Layout B (split, QS-C), both showing .claude/agents/ symlink. 160/161 tests pass.

## Next Task

5. Test all quick-start paths — coder
