# Task 4 Summary — One-task-per-iteration enforcement

## What was done

Added a post-iteration validator that detects when an agent completes more than
one task in a single loop iteration.

## RED commit

`7b5c58d` — 5 test cases in `tests/test_single_task_enforcement.sh` all fail
because `validate_single_task_completion` does not exist.

## GREEN commit

`87ee3a2` — Two changes:

1. **`lib/post-run.sh`**: Added `validate_single_task_completion(before, after)`.
   Counts `- [x]` lines in both files; if the difference exceeds 1, returns 1
   (violation).

2. **`ralph-loop.sh`**: Added snapshot+check in the serial build path:
   - Before agent dispatch: `cp implementation-plan.md` to `$RALPH_RUN/plan-before-N.md`
   - After success: call `validate_single_task_completion`; on violation, record
     circuit-breaker failure and `break` the loop.

## Files modified

- `lib/post-run.sh` — new function (16 lines)
- `ralph-loop.sh` — snapshot (3 lines) + check (10 lines)
- `tests/test_single_task_enforcement.sh` — new test file (5 cases)

## Test results

```
tests/test_single_task_enforcement.sh:    5/5 passed
tests/test_terminal_checkpoint_dispatch.sh: 6/6 passed (regression check)
ralph-loop.sh: bash -n syntax OK
```
