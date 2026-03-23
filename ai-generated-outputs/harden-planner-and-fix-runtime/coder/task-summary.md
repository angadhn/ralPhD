# Task 2 Summary — validate_plan_tdd_structure

## What was done
Added `validate_plan_tdd_structure()` function and wired it as a pre-loop gate in `ralph-loop.sh`.

The function scans unchecked coder TDD tasks in the implementation plan and verifies each has all four required sub-fields: `RED:`, `GREEN:`, `VERIFY:`, `Commits:`. If any field is missing, the build is blocked with a clear error message.

## Files changed
- `lib/post-run.sh` — Added `validate_plan_tdd_structure(plan_path)` after `validate_single_task_completion`
- `ralph-loop.sh` — Added pre-loop validation call before the main `while true` loop
- `tests/test_plan_tdd_validation.sh` — New test file with 5 tests (A-E)

## TDD proof
- RED commit: `0df49bb` — all 5 tests fail (function not found)
- GREEN commit: `7d9036f` — all 5 tests pass

## Test results
- `tests/test_plan_tdd_validation.sh`: 5/5 passed
- `tests/test_single_task_enforcement.sh`: 5/5 passed (no regressions)

## Deviation from plan
Fixed a grep bug: task lines start with `- [ ]` which grep interpreted the leading dash as an option flag. Added `--` separator to `grep -n -F -- "$task_line"`.
