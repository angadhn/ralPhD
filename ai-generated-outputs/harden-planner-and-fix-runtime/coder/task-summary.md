# Task 4 Summary — Set-based task detection

## What was changed
Rewrote `validate_single_task_completion()` in `lib/post-run.sh` from count-based delta to set-based diff detection.

**Old approach:** `after_count - before_count` — missed check+uncheck swaps where the net delta was ≤1 but multiple new tasks were actually checked.

**New approach:** Extract task numbers from `- [x]` lines in both files, use `comm -13` to find newly-checked tasks (present in after but not before), count those.

## Files modified
- `tests/test_single_task_enforcement.sh` — Added test G (check+uncheck swap with 2 newly checked)
- `lib/post-run.sh` — Rewrote `validate_single_task_completion` (lines 25-43)

## TDD proof
- **RED commit:** 5298267 — test G fails with count-based implementation (delta=1 masks 2-task violation)
- **GREEN commit:** b38dcf7 — all 7 enforcement tests + 5 TDD validation tests pass

## Test results
- `tests/test_single_task_enforcement.sh`: 7/7 passed
- `tests/test_plan_tdd_validation.sh`: 5/5 passed
