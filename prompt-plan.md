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

### Interaction style

Use the `ask_choice` and `ask_question` tools for ALL user interaction.
Do NOT output questions as plain text — always use the tools so the
model waits for the user's response before continuing.

- **ask_choice** — for questions with clear categories (MCQ). The user
  sees numbered options and picks one, or types a free-text answer.
- **ask_question** — for open-ended questions where you need free text.

Call **one tool at a time**. Read the result, then decide the next
question based on the answer. The flow is:

1. Call ask_choice or ask_question with one question.
2. Read the user's response from the tool result.
3. Use the response to adapt the next question.

If the workspace scan (1b) reveals something relevant, weave it into
the next question naturally ("I see you have reviewer feedback in
human-inputs/ — are we doing a revision?") rather than dumping a
separate report.

### 1a. What kind of project?

Present a numbered menu. Ask the user to pick one (or describe
something else):

```
What kind of project is this?

1. Write a paper — conference paper, journal article, thesis chapter
2. Literature review — survey a topic, build and synthesize a corpus
3. Grant / research proposal — funding application, research plan
4. Revision / resubmission — revise a draft from reviewer feedback
5. Coding / analysis — scripts, experiments, data pipelines, tooling
6. Something else — describe it and I'll adapt
```

Record the choice as `PROJECT_TYPE` — all subsequent questions branch
on this.

### 1b. Workspace scan

Before asking more questions, silently scan the workspace for signals
and report a brief summary of what exists:

- `.tex` / `.bib` files → note which sections exist
- `inputs/` or `human-inputs/` → prior submissions, reviewer feedback, venue docs
- `specs/publication-requirements.md` → venue already configured
- `AI-generated-outputs/` → previous ralPhD thread exists
- Source code files → note language and structure
- `corpus/` or `papers/` → literature already gathered

Report what you found in 2-3 lines. Ask the user to confirm or correct.

### 1c. Type-specific follow-ups

Ask follow-up questions adapted to the PROJECT_TYPE. Present options
as numbered lists where possible — the user can pick a number or
type a short answer.

**If Write a paper (1):**

```
Who is the audience?
1. ML / AI conference (NeurIPS, ICML, ICLR, AAAI, etc.)
2. Robotics / controls (ICRA, IROS, RSS, CoRL, etc.)
3. Domain-specific journal (which field?)
4. Thesis chapter / dissertation
5. Other — describe
```

Then ask:
- Do you have an outline or structure in mind, or should I propose one?
- What stage are you at — starting from scratch, have notes, or
  have a partial draft?
- Any page / word limits or formatting requirements?

**If Literature review (2):**

```
What kind of review?
1. Broad survey — map the landscape of a topic
2. Focused synthesis — compare specific methods/approaches
3. Background section — lit review as part of a larger paper
4. Systematic review — structured search with inclusion criteria
```

Then ask:
- What is the topic or research question?
- Do you already have papers to include, or should I search?
- Target scope — how many papers roughly? (10? 30? 50+?)

**If Grant / research proposal (3):**

```
What stage?
1. Starting from scratch — need to develop the idea
2. Have a research question — need to structure the proposal
3. Have a draft — need to refine and strengthen it
```

Then ask:
- What funding body / call? (affects structure and tone)
- Page or word limit?
- Deadline?

**If Revision / resubmission (4):**

```
What are you revising from?
1. Peer reviewer feedback (have reviews)
2. Advisor / collaborator feedback
3. Self-revision — improving a previous draft
4. Resubmission to a different venue
```

Then ask:
- Is the reviewer feedback in `human-inputs/`? If not, where?
- Are there specific points you agree/disagree with?
- Same venue or different target?

**If Coding / analysis (5):**

```
What needs to happen?
1. New analysis — build something from scratch
2. Extend existing code — add a feature or capability
3. Fix / debug — something is broken
4. Refactor / clean up — improve structure, tests, docs
5. Data pipeline — processing, transformation, visualization
```

Then ask:
- What language / framework?
- Is there existing code to build on, or greenfield?
- Any specific outputs expected (plots, tables, models)?

**If Something else (6):**

Ask the user to describe the project in a few sentences, then
adapt by picking the closest built-in type or designing a
custom flow.

### 1d. Autonomy level

Present as a numbered choice:

```
How much oversight do you want?

1. Full autopilot — agents run the whole plan, only stops on errors
2. Stage gates — runs within a phase, pauses between phases for review (recommended)
3. Step-by-step — pauses after every single task for your approval
```

If the user picks stage gates (or has no preference, default to it),
ask one follow-up: "Which transitions should pause for review?" and
suggest common gates based on the project type:
- Writing: after lit review → before drafting, after draft → before editing
- Coding: after implementation → before testing, after tests → before deploy
- Revision: after analysis → before rewrite, after rewrite → before final check

Record the choice in `implementation-plan.md` as a frontmatter field
(`**Autonomy:** autopilot | stage-gates | step-by-step`) so build mode
can enforce it.

Also set the **Architecture** field:
(`**Architecture:** serial | parallel | auto`). Set to `parallel` if
any phases have independent agents (see Step 5), `serial` if all phases
are strictly sequential, or `auto` to let the loop decide.

### 1e. Constraints

Ask ONE final question that covers remaining constraints. Adapt to
what you already know — skip anything already answered:

```
Anything else I should know? (pick any that apply, or say "no")

1. Specific venue / format requirements
2. Tight deadline (affects how many review passes to plan)
3. Parts you want to handle yourself (vs. delegate to agents)
4. No, that covers it
```

After this intake, you have enough to proceed to Step 2.

## Step 2 — Agent inventory

Read `.claude/agents/README.md` (framework file — see Path Context if present)
and the agent files. Do the right agents exist for this task, or does the
session suggest new ones are needed?

### Custom agents

1. Check the workspace `.claude/agents/` directory for existing custom agents.
2. If the built-in agents don't fit the task, create a custom agent:
   - Read `agent-template.md` (framework file) for the required structure.
   - Draft a focused agent prompt (~60 lines). Show it to the user for approval.
   - Create the file in the **workspace** `.claude/agents/` directory (not RALPH_HOME) —
     this keeps customizations project-local.
   - Custom agents automatically get DEFAULT_TOOLS (read_file, write_file,
     git_commit, list_files, code_search). Specialized tools (pdf, search, etc.)
     require manual registration in `tools/__init__.py` `AGENT_TOOLS` —
     note this in the plan if needed.
3. **Name collisions**: if a workspace agent has the same name as a built-in
   agent, the workspace version takes priority. Use this intentionally to
   override built-in behavior for a specific project, but call it out in
   the plan so it's not surprising.

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
