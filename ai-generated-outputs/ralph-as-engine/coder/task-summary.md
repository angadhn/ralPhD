# Task 3–4 Summary — GitHub Actions Workflow + Init Step

## Task 3: Create `.github/workflows/ralph-run.yml`

Created a GitHub Actions workflow_dispatch workflow that makes ralPhD invocable as an engine from external triggers (Howler, API, manual).

### Files changed
- **`.github/workflows/ralph-run.yml`** (new) — workflow_dispatch with 7 inputs

### Workflow inputs
| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| thread | yes | — | Thread name for checkpoint/outputs |
| prompt | yes | — | Task prompt written to inbox.md |
| autonomy | no | stage-gates | autopilot / stage-gates / step-by-step |
| target_repo | no | (empty=self) | owner/name of target project |
| target_ref | no | main | Branch of target repo |
| max_iterations | no | 5 | Safety iteration cap |
| loop_mode | no | build | build or plan |

### Design decisions
- Two checkouts: ralPhD as `ralph-home/`, target project as `workspace/`
- RALPH_HOME set to `ralph-home/` in all steps
- All inputs passed via env vars (no shell injection)
- 60-minute timeout + configurable iteration cap
- Artifact upload of outputs, checkpoint, logs (30-day retention)
- Job summary with checkpoint state, usage, and human review flags

## Task 4: Add `.ralph` init step

Enhanced `init-project.sh` with `--ci` mode and updated the workflow init step.

### Files changed
- **`scripts/init-project.sh`** — added `--ci` flag
- **`.github/workflows/ralph-run.yml`** — enhanced init step

### What `--ci` mode does differently
- **Copies** specs/, templates/, .claude/agents/ instead of symlinking
- **Skips** ralphd launcher creation (not needed in CI)
- **Skips** brownfield git detection (workspace is already a checkout)

### Workflow init step logic
1. First-time project: runs `init-project.sh --ci .` to scaffold ralph files
2. Existing project: skips init, uses existing checkpoint/plan
3. Template injection: replaces `<thread-name>`, `<thread name>`, `<date>` placeholders
4. Writes prompt to inbox.md
5. Sets autonomy in implementation-plan.md
6. Configures git user for agent commits

## Test results
- YAML validation: ✅
- `init-project.sh --ci` test: ✅ (real dirs, no symlinks, no ralphd)
- `init-project.sh` (local mode): ✅ (backward compatible, symlinks work)
- Full integration test deferred to Task 5
