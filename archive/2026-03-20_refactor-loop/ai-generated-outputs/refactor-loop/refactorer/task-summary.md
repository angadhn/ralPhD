# Task 3 Summary — Extract model/effort resolution

## What was changed

Added `resolve_model_and_effort()` to `lib/exec.sh` — sets globals `CLI_MODEL` and `EFFORT_FLAG` from a model name and agent name.

Replaced 3 duplicated patterns in `ralph-loop.sh`:
1. **Plan mode** (line 140): was `PLAN_CLI_MODEL`, `PLAN_EFFORT`, `PLAN_EFFORT_FLAG`
2. **Pipe mode fallback** (line 358): was `BUILD_CLI_MODEL`, `FALLBACK_EFFORT`, `FALLBACK_EFFORT_FLAG`
3. **Interactive Anthropic** (line 472): was `INTERACTIVE_CLI_MODEL`, `AGENT_EFFORT`, `EFFORT_FLAG`

Each 4-9 line block reduced to 1-2 lines.

## Verification

- `bash -n ralph-loop.sh` — PASS (before and after)
- `bash -n lib/exec.sh` — PASS (before and after)
- All old variable names (`PLAN_CLI_MODEL`, `BUILD_CLI_MODEL`, etc.) confirmed removed
- No collision with `CLI_MODEL` from `parse_loop_args` (consumed before helper is called)

## Metrics

- Lines changed: 27 added, 27 removed (net zero — complexity reduction, not LOC reduction)
- 6 unique variable names eliminated, replaced by 2 standardized globals
