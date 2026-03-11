# Human Review Needed

## Phase 0 Complete — Archive Hygiene

**Thread:** ralph-as-engine
**Date:** 2026-03-11

### What was completed

`scripts/archive.sh` now archives all per-thread files on thread completion:

| File/Dir | Action |
|----------|--------|
| `ai-generated-outputs/<thread>/` | Moved to archive |
| `ai-generated-outputs/reflections/*.md` | Moved to archive (`.gitkeep` preserved) |
| `inbox.md` | Copied to archive if non-empty, then truncated |
| `CHANGELOG.md` | Moved to archive, reset to blank header |
| `/tmp/ralph-*` | Deleted (8 state files) |

Previously only `checkpoint.md`, `implementation-plan.md`, `HUMAN_REVIEW_NEEDED.md`, and `iteration_count` were handled.

### What the next phase will do

**Phase 1 — GitHub Actions workflow for ralph-loop:**
- Task 3: Create `.github/workflows/ralph-run.yml` (workflow_dispatch)
- Task 4: Add `.ralph` init step (template copying for new repos)
- Task 5: Test workflow locally

This will make ralPhD invocable as a reusable engine from external triggers.

### Review checklist

- [ ] Review `scripts/archive.sh` changes (3 commits: d31a30c, 357e93e, 624e5dc)
- [ ] Confirm archive behavior looks correct
- [ ] Approve proceeding to Phase 1
