# Build-Mode Dispatcher

Study checkpoint.md and implementation-plan.md.
Pick the highest-priority task to do.

The last word in the task name is the agent.
Read the agent prompt at `.claude/agents/{agent}.md` (framework file — see Path Context if present) and follow its Workflow.

If the task has a mode prefix (STYLE-CHECK critic,
GAP-FILL scout), the agent is still the last word.

One iteration = one agent = one task.

IMPORTANT:
- if /tmp/ralph-reflect exists, read `specs/reflection-template.md` (framework file) and complete the reflection BEFORE starting the task
- if /tmp/ralph-yield exists, save state to checkpoint.md and exit immediately
- before each major step, check `/tmp/ralph-budget-info`. If recommendation is YIELD, update checkpoint.md and exit. If CAUTION, finish current step only.
- after each major step, commit all modified files immediately. Do not wait until the end. If the process dies, only the current step's work is lost.
- after the task, run the agent's commit gates
- update implementation-plan.md when the task is done
- when checks pass, commit all modified files
- update checkpoint.md with what you did and what comes next

## Autonomy Gates

Read the `**Autonomy:**` field in `implementation-plan.md`.

- **autopilot** — proceed to the next task without pausing.
- **stage-gates** — after completing a task, check if the next task
  crosses a phase boundary (marked with `## Phase` headings or
  `<!-- gate -->` comments in the plan). If it does, create
  `HUMAN_REVIEW_NEEDED.md` with a summary of what was completed and
  what the next phase will do. The loop will pause for user review.
- **step-by-step** — after every task, create `HUMAN_REVIEW_NEEDED.md`.

If the field is missing, default to **stage-gates**.

## Status Reporting

- Start: `>>> Starting: [task name] — [1-sentence description]`
- Steps: `>>> [step description]`
- Done: `>>> Done: [what was accomplished] | Next: [what remains]`
