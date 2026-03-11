# Task 3 Summary — Create `.github/workflows/ralph-run.yml`

## What was done
Created a GitHub Actions workflow_dispatch workflow that makes ralPhD invocable as an engine from external triggers (Howler, API, manual).

## Files changed
- **`.github/workflows/ralph-run.yml`** (new) — 229 lines

## Design decisions
1. **Two checkouts:** ralPhD checked out as `ralph-home/`, target project as `workspace/`. When no target repo is specified, workspace symlinks to ralph-home (self-mode).
2. **RALPH_HOME separation:** All steps that run ralph code set `RALPH_HOME` to `${{ github.workspace }}/ralph-home`, matching the RALPH_HOME pattern already in `ralph-loop.sh`.
3. **Input security:** All `workflow_dispatch` inputs are passed to shell via `env:` blocks, never interpolated directly in `run:` scripts (prevents shell injection).
4. **Auth:** Uses `ANTHROPIC_API_KEY` secret. Model configurable via `CLAUDE_MODEL` repository variable (defaults to `claude-sonnet-4-6` for CI cost control).
5. **Target repo token:** Uses `TARGET_REPO_TOKEN` secret for cross-repo checkout (PAT with repo access). Falls back gracefully if not set.
6. **Safety:** 60-minute job timeout + configurable `max_iterations` cap (default: 5).

## Workflow inputs
| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| thread | yes | — | Thread name for checkpoint/outputs |
| prompt | yes | — | Task prompt written to inbox.md |
| autonomy | no | stage-gates | autopilot / stage-gates / step-by-step |
| target_repo | no | (empty=self) | owner/name of target project |
| target_ref | no | main | Branch of target repo |
| max_iterations | no | 5 | Safety iteration cap |
| loop_mode | no | build | build or plan |

## Test results
- YAML validation: ✅ (parsed without errors)
- Structure check: ✅ (10 steps, 7 inputs, all `uses:` pinned to @v4/@v5)
- Injection check: ✅ (no raw `${{ }}` in `run:` script bodies)
- Full integration test deferred to Task 5
