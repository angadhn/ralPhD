# Task 2 Summary — Consolidate plan mode into early-exit block

## What changed

**File:** `ralph-loop.sh`

Moved plan mode from being interleaved across multiple sections into a single
self-contained early-exit block immediately after agent detection.

### Before
- Plan mode detection at line 105 (agent detection section) — set CURRENT_AGENT, skipped to next section
- Orchestrated mode guard: `$ARCH_MODE = "orchestrated" && $LOOP_MODE = "build"` — plan skipped via guard
- Parallel mode guard: `$ARCH_MODE = "parallel" && $LOOP_MODE = "build"` — plan skipped via guard
- Shared prompt-building section ran for both plan and build
- Interactive branch contained a `if [ "$LOOP_MODE" = "plan" ]` block with `break`

### After
- Single plan mode block after agent detection: detects plan → loads prompt → absorbs inbox → resolves model → starts monitor → archive check → runs claude CLI → logs usage → breaks
- Orchestrated mode guard simplified to `$ARCH_MODE = "orchestrated"` (plan already exited)
- Parallel mode guard simplified to `$ARCH_MODE = "parallel"` (plan already exited)
- Interactive branch no longer contains plan handling; starts with `if is_openai_model`

## Verification

| Check | Before | After |
|-------|--------|-------|
| `bash -n ralph-loop.sh` | PASS | PASS |
| `shellcheck -S warning` | 6 SC2034 (pre-existing) | 6 SC2034 (identical) |

## Metrics
- Lines added: 78, removed: 61 (net +17 — plan block is self-contained but slightly larger due to inlining prompt/inbox logic that was previously shared)
- No behavior changes
