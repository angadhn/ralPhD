# Plan-Mode Dispatcher

## Step 0 — Check for completed plan

Read `implementation-plan.md` if it exists. If **every** task is checked
off (`- [x]`), the current thread is complete.

Ask the user: "All tasks are done. Archive this thread and start fresh?"

- If yes: run `./scripts/archive.sh`, then continue to step 1 with a
  clean slate.
- If no: skip archiving and continue to step 1 (user may want to add
  more tasks to the existing plan).

If the plan has unchecked tasks, skip this step entirely.

## Step 1 — Gather goal

Ask the user for their research goal if not already stated.

## Step 2 — Agent inventory

Read `.claude/agents/README.md` and the agent files. Do the right agents
exist for this task, or does the session suggest new ones are needed?

## Step 3 — Context

Read `checkpoint.md` and `implementation-plan.md` if they exist.

## Step 4 — Plan

Develop the implementation plan through conversation — ask questions,
propose structure, refine based on feedback.

Your output is `implementation-plan.md` — a prioritized checklist that
build mode executes. Each task names an agent as its last word
(same convention as build mode).
