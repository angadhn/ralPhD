# Task Summary — Phase 4: Update Docs

**Task:** 4. Update docs
**Thread:** fix-init-paths
**Date:** 2026-03-13

## Files Changed

| File | Change |
|------|--------|
| `README.md` | Updated Quick Start B description to clarify content dirs are created inside workspace (not cwd); added `.claude/agents/` to symlink list |
| `specs/api-contract.md` | Replaced single "Layout" section with two named layouts: Layout A (all-in-one, Quick Start B) and Layout B (split, Quick Start C); added `.claude/agents/` symlink to both layouts |

## What Was Done

- **README.md**: The Quick Start B paragraph now states that content directories (`papers/`, `corpus/`, etc.) are created inside the workspace argument regardless of current working directory — addressing the core bug fixed in Phase 1.
- **api-contract.md**: Added "Layout A: all-in-one workspace (Quick Start B)" showing the `my-paper/` flat layout where everything lives in one directory. Renamed the existing split-layout section to "Layout B: split layout (Quick Start C)" to make clear it only applies to brownfield `.ralph/` setups. Both layouts now show `.claude/agents/ → $RALPH_HOME/.claude/agents` symlink (added in Phase 2).
- **Quick Start A** (run from ralPhD repo): no changes needed — README already correctly shows `cd ralPhD && ./ralph-loop.sh`.

## Test Results

160/161 tests pass — same as before Phase 4. The 1 failing test is the pre-existing failure unrelated to this change.
