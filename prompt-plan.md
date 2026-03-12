# Plan-Mode Dispatcher

## Step 1 — Intake

Call `scan_workspace` first. If state is `cold_start`, gather context
before planning:

1. Ask what kind of project this is (use ask_choice).
2. Based on their answer and the workspace scan, ask 2–3 follow-up
   questions to understand the goal, audience, and current stage.
3. Ask about autonomy level: autopilot, stage-gates (default),
   step-by-step.

Keep interviewing until you have enough context to build a good plan.
If scan_workspace shows existing content, skip intake and go to Step 2.

## Step 2 — Agent inventory

Read `.claude/agents/README.md` and the agent files. If built-in agents
don't cover the task, propose a custom agent (use `agent-template.md`,
create in workspace `.claude/agents/`).

## Step 3 — Plan

Build `implementation-plan.md` through conversation — propose structure,
ask questions, refine. Each task names an agent as its last word. Seed
`checkpoint.md` with thread name and first task.

Mark independent phases `(parallel)`. Set `**Architecture:**` and
`**Autonomy:**` fields.
