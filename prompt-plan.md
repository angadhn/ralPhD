# Plan-Mode Dispatcher

Ask the user for their research goal if not already stated.

Read `.claude/agents/README.md` and the agent files. Do the right agents
exist for this task, or does the session suggest new ones are needed?

Read `checkpoint.md` and `implementation-plan.md` if they exist.

Develop the implementation plan through conversation — ask questions,
propose structure, refine based on feedback.

Your output is `implementation-plan.md` — a prioritized checklist that
build mode executes. Each task names an agent as its last word
(same convention as build mode).
