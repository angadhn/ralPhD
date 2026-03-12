# lib/

Sourced shell helpers for `[ralph-loop.sh](../ralph-loop.sh)`.

The loop entrypoint stays stable for operators:

```bash
./ralph-loop.sh
./ralph-loop.sh plan
./ralph-loop.sh -p
./ralph-loop.sh -p plan
```

These helpers keep the shell logic separated by concern so the loop script can stay small and readable.

| File | Responsibility |
|------|----------------|
| `config.sh` | CLI arg parsing, `RALPH_HOME` resolution, architecture resolution, bootstrap state |
| `detect.sh` | Parse `checkpoint.md` / `implementation-plan.md` for next-task and phase information |
| `monitor.sh` | Context budgeting, yield recommendation, heartbeat/status output |
| `exec.sh` | Model resolution (`resolve_model`, `is_openai_model`, `resolve_context_window`) and parallel-phase execution |
| `post-run.sh` | Usage logging, eval capture, human-review gate, changelog/circuit-breaker helpers |

Design notes:

- These files are sourced by `ralph-loop.sh`; they are not standalone entrypoints.
- Shared helpers take explicit file paths where that improves testability, especially in `detect.sh`.
- Runtime behavior should remain unchanged; this split is for maintainability and testability.
