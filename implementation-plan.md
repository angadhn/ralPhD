# Implementation Plan — refactor-loop

**Thread:** refactor-loop
**Created:** 2026-03-20
**Architecture:** serial
**Autonomy:** stage-gates

## Tasks

- [ ] 1. Extract helper functions from ralph-loop.sh into lib/post-run.sh — **refactorer**
      - `cleanup_pid()` — kill/wait/reset pattern (currently repeated 4x in ralph-loop.sh)
      - `log_interactive_session()` — build SESSION_FILE path + call log_interactive_session_usage (duplicated for plan and build interactive modes)
      - `post_iteration()` — capture_eval_metrics + handle_human_review_gate (duplicated for pipe and interactive modes)
      Verify: `bash -n ralph-loop.sh` + `shellcheck ralph-loop.sh` pass before and after

- [ ] 2. Consolidate plan mode into early-exit block at top of loop (depends: 1) — **refactorer**
      - Move plan execution up to where plan detection happens (around the LOOP_MODE check)
      - Single block: detect plan → load prompt → absorb inbox → run claude CLI → log usage → break
      - Remove `LOOP_MODE = "build"` guards from orchestrated and parallel sections since plan already exited
      Verify: `bash -n ralph-loop.sh` + test `./ralph-loop.sh plan` interactively

- [ ] 3. Extract model/effort resolution into helper function (depends: 1) — **refactorer**
      - `resolve_model_and_effort()` — returns CLI_MODEL and EFFORT_FLAG (pattern repeated 3x)
      - Add to lib/exec.sh (where resolve_model and resolve_effort already live)
      Verify: `bash -n ralph-loop.sh` passes
