# Task 1 Summary — Archive all per-thread files

**Agent:** coder
**Task:** Update `scripts/archive.sh` to archive all per-thread files

## Changes

**File modified:** `scripts/archive.sh`

Added three new archive steps between the existing checkpoint/plan archiving and the template restoration:

1. **Per-thread agent outputs** (`ai-generated-outputs/<thread>/`): Moved to `archive/<date>_<thread>/ai-generated-outputs/` if the directory exists.

2. **Reflections** (`ai-generated-outputs/reflections/*.md`): Moved to `archive/<date>_<thread>/reflections/`, preserving `.gitkeep` in the source directory.

3. **Inbox content** (`inbox.md`): Copied to archive if non-empty, then truncated to reset for the next thread.

## What was NOT changed

- `logs/usage.jsonl`: Running log across all threads. The existing thread-summary append logic is sufficient; copying the full file per-archive would be redundant.
- No template changes needed — inbox is reset via truncation, not template copy.

## Test results

- `bash -n` syntax check: passed
- `find` command for reflections verified against live files: correctly discovers `reflection-iter-1.md` and `reflection-iter-2.md`

---

# Task 2 Summary — Audit for stale files

**Agent:** coder
**Task:** Audit for other files that should be reset/archived on thread completion

## Audit findings

Audited all files created/modified by `ralph-loop.sh` and `ralph_agent.py` during execution.

**Files that needed archiving/cleanup (now fixed):**

1. **CHANGELOG.md** — Accumulates per-iteration entries across all threads via `ralph-loop.sh` line 575. Now moved to archive on thread completion and reset to a blank header.

2. **/tmp/ralph-*** — 8+ temp files created during loop execution (`ralph-context-pct`, `ralph-yield`, `ralph-budget-info`, `ralph-output.json`, `ralph-statusline-log`, `ralph-monitor-start`, `ralph-reflect`, `ralph-test-output.json`). Could leak state across thread boundaries. Now cleaned on archive.

**Files confirmed as not needing cleanup:**
- `prompt-build.md`, `prompt-plan.md` — framework-level, read-only
- `context-budgets.json` — static configuration
- `.claude/agents/`, `specs/`, `templates/` — framework files
- `logs/usage.jsonl` — intentional running log (thread summary already appended)
- `__pycache__/` — already gitignored, harmless

## Changes

**File modified:** `scripts/archive.sh` — added CHANGELOG.md archive+reset and /tmp/ralph-* cleanup
