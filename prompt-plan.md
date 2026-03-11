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

## Step 1 — Cold-start intake (when checkpoint + plan are empty/template)

If `checkpoint.md` and `implementation-plan.md` are both uninitialized
(contain placeholder `<` markers or are empty), run a structured Q&A
before planning. Skip this step if either file has real content.

### 1a. What kind of work?

Ask the user what they're trying to do. Don't assume — the workspace
could be any of:

- **Writing** — paper, proposal, rewrite, response to reviewers
- **Literature review** — survey a topic, build a reading corpus
- **Coding** — analysis scripts, experiments, tooling
- **Editing** — revise an existing draft (IFP rewrite, resubmission)

If the workspace is a code repository (has source files, not just .tex),
note that — it changes which agents and tools are relevant.

### 1b. What exists already?

Scan the workspace for signals:

- `.tex` / `.bib` files → writing project, note which sections exist
- `inputs/` directory → prior submissions, reviewer feedback, venue docs
- `specs/publication-requirements.md` → venue already configured
- `AI-generated-outputs/` → previous ralPhD thread exists
- Source code files → coding project, note language and structure
- `corpus/` or `papers/` → literature already gathered

Report what you found. Ask the user to confirm or correct.

### 1c. What's the goal this session?

Now that you know the work type and existing state, ask a focused
question. Examples:

- "You have a draft with intro + methods. What's next — write results,
  or revise what's there?"
- "No .tex files yet. Are we starting from a literature review, or do
  you have an outline?"
- "This looks like a code repo. What needs to happen — new analysis,
  fix something, or add a feature?"
- "There's reviewer feedback in inputs/. Are we doing a point-by-point
  rewrite?"

### 1d. Autonomy level

Ask the user how much oversight they want. Frame it as a spectrum:

- **Full autopilot** — agents run the entire plan uninterrupted.
  Only stops on errors or when the plan is complete.
- **Stage gates** — runs autonomously within a phase, pauses between
  phases for review. (e.g., finish all lit review tasks, pause before
  writing starts). This is the default if the user has no preference.
- **Step-by-step** — pauses after every task for approval before
  continuing to the next.

Record the choice in `implementation-plan.md` as a frontmatter field
(`**Autonomy:** autopilot | stage-gates | step-by-step`) so build mode
can enforce it.

Also set the **Architecture** field:
(`**Architecture:** serial | parallel | auto`). Set to `parallel` if
any phases have independent agents (see Step 5), `serial` if all phases
are strictly sequential, or `auto` to let build mode decide.

For stage gates: ask which transitions warrant a pause. Common gates:
- After literature review, before writing begins
- After first draft, before editing passes
- After edits, before final review / submission prep

### 1e. Constraints and preferences

Ask about anything else that shapes the plan:

- Venue / format requirements (if not already in specs/)
- Deadline pressure (affects how many review cycles to plan)
- What the user wants to handle themselves vs. delegate to agents

After this intake, you have enough to proceed to Step 2.

## Step 2 — Agent inventory

Read `.claude/agents/README.md` (framework file — see Path Context if present)
and the agent files. Do the right agents exist for this task, or does the
session suggest new ones are needed?

## Step 3 — Context

Read `checkpoint.md` and `implementation-plan.md` if they exist (and
have real content beyond templates).

## Step 4 — Plan

Develop the implementation plan through conversation — ask questions,
propose structure, refine based on feedback.

Your output is `implementation-plan.md` — a prioritized checklist that
build mode executes. Each task names an agent as its last word
(same convention as build mode).

IMPORTANT: Also seed `checkpoint.md` with the thread name and first
task (if it isn't already seeded from template). Build mode reads
`checkpoint.md` to detect the next agent — if it's still a template,
build mode cannot start.

## Step 5 — Parallelism analysis

After generating the plan, analyze agent dependencies within each phase:

1. For each `## Phase` heading, examine the tasks within it.
2. Two tasks are **independent** if neither reads files that the other writes,
   and they don't modify the same state files (checkpoint.md is excluded —
   each agent updates only its own task entry).
3. If all tasks in a phase are independent, mark the phase heading with
   `(parallel)` suffix: `## Phase 3 — Critical review (parallel)`.
4. If tasks have dependencies (e.g., one generates data another analyzes),
   leave the phase unmarked (serial execution).

Common parallel-safe patterns:
- Multiple critics reviewing different sections simultaneously
- Scout + research-coder working on independent sub-problems
- Multiple deep-readers analyzing different papers

Common serial-required patterns:
- Writer → editor → reviewer (each depends on prior output)
- Scout → deep-reader (reader needs scout's corpus)
- Any task that reads checkpoint.md to determine what to do next

Set `**Architecture:** parallel` if any phases are annotated `(parallel)`.
Set `**Architecture:** serial` if no phases qualify.
