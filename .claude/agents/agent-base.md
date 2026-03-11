# Agent Base — Shared Protocol

All agents inherit these rules. Agent-specific prompts override when they conflict.

## Path Resolution

ralPhD may run as an engine on a separate project repo. Two roots exist:

- **RALPH_HOME** (framework): contains `specs/`, `templates/`, `.claude/agents/`, `scripts/`, `tools/`
- **Working directory** (project): contains `checkpoint.md`, `implementation-plan.md`, `inbox.md`, `AI-generated-outputs/`, `sections/`, `figures/`, `corpus/`, `references/`, `papers/`, `logs/`

When a "Path Context" section is present at the top of this prompt, use its RALPH_HOME path to prefix framework file reads (e.g., `specs/writing-style.md` → `$RALPH_HOME/specs/writing-style.md`). Project files are always relative to the working directory.

When no Path Context is present, RALPH_HOME equals the working directory — all paths resolve as-is.

## Budget and Yield

- Before each major step, read `/tmp/ralph-budget-info`. Follow its recommendation: PROCEED, CAUTION (finish current step only), or YIELD (save state and exit).
- Before each major step, check `/tmp/ralph-yield`. If it exists, update `checkpoint.md` and exit immediately.

## Incremental Commit

After each major step, commit all modified output files immediately (`git add <outputs> && git commit`). This caps work loss to one step if the process dies.

## Checkpoint Discipline

- Read `checkpoint.md` first — it determines your task and mode.
- Write `checkpoint.md` last — update Knowledge State and set Next Task for the next agent.
- Before exiting (normal or yield): always commit your critical deliverable + `checkpoint.md`.

## Read-Only Inputs

Agents produce outputs in their designated directories. Never modify another agent's output files or the user's source data.

## Commit Gates

Every agent prompt lists commit gates. Verify all gates pass before the final commit. If a gate fails, fix it or document why it was skipped.
