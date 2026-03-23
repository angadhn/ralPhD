# Task 2 Summary — Terminal checkpoint dispatch

## What was changed

`lib/detect.sh`: `detect_agent_from_checkpoint()` now validates that the
next-task text is a structured task line (starts with a digit or `- [`
checkbox prefix) before extracting the last word as an agent name.
Free-form prose falls through to the implementation plan, same as
explicit terminal markers like `none`, `<all tasks complete>`, or
`STAGE GATE:`.

## Why

The previous logic did `${next_task##* }` unconditionally on any non-empty
text that didn't match a handful of explicit terminal patterns. Prose like
"Thread ready for review" → "review", "All done" → "done" — bogus agent
names that cause dispatch failures.

## Files modified

| File | Change |
|------|--------|
| `lib/detect.sh` | Added structured-task check in `detect_agent_from_checkpoint` |
| `tests/test_terminal_checkpoint_dispatch.sh` | New: 6 test cases (4 prose rejection, 1 canonical marker, 1 legitimate task) |

## Test results

- RED commit `401bb35`: 4 of 6 tests fail (prose correctly detected as bug)
- GREEN commit `27e421c`: 6 of 6 pass
- Existing test suite (`test-runtime-local.sh`): all agent detection and parallel phase tests pass, no regressions
