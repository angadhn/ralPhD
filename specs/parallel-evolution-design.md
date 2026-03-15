# Design: Parallel Execution — Next Evolution

**Status:** Design document (not yet implemented)
**Prerequisite:** Worktree isolation (steps 1-9, committed)
**Context:** After implementing plan-driven parallel worktree isolation, we identified capabilities that require an AI orchestrator agent rather than deterministic bash logic.

## What we have now

Plan-driven parallelism: the implementation plan declares `(parallel)` phases with `(depends: N)` annotations. `ralph-loop.sh` creates worktrees, spawns agents, merges branches, reconciles shared files, and cleans up. All deterministic — no AI judgment at runtime.

**Limitations of plan-driven parallelism:**
- All tasks in a phase start together, finish together (phase gates)
- No runtime adaptation (if a scout finds nothing useful, the plan doesn't adjust)
- No sub-tasking (if a task is too large, nobody splits it)
- No thread-aware pipelines (thermal thread can't advance while structural is still scouting)

## 1. Orchestrator Agent

**What:** A lightweight agent that runs at phase boundaries to make dispatch decisions.

**When it runs:** Between phases, not during. The bash loop calls it like any other agent, but its output is a JSON dispatch instruction rather than file changes.

**What it decides:**
- Which tasks from the plan can run in parallel (confirms/overrides plan annotations)
- How to batch tasks (e.g., "run 3 scouts now, 3 more after" based on rate limits)
- Whether to adapt the plan based on previous phase results (e.g., "scouts found only 10 papers — skip triage, go straight to deep reading")
- Whether a coarse task needs splitting before dispatch

**What it does NOT do:**
- Long-running work (it makes a decision and exits)
- Monitor agents during execution (the bash loop does that)
- Merge results (merge scripts do that)

**Agent file:** `.claude/agents/orchestrator.md`

**Output format:**
```json
{
  "action": "dispatch",
  "tasks": [
    {"task_num": 8, "agent": "resume-tailor", "worktree": true},
    {"task_num": 9, "agent": "resume-tailor", "worktree": true}
  ],
  "batch_size": 3,
  "reasoning": "Rate limiting observed in Phase 1 — batching 3 at a time"
}
```

Or for plan adaptation:
```json
{
  "action": "adapt",
  "changes": [
    {"task_num": 4, "change": "skip", "reason": "Scout found 0 relevant papers for this thread"},
    {"task_num": 7, "change": "split", "subtasks": ["7a. Synthesize thermal thread", "7b. Synthesize structural thread"]}
  ]
}
```

**Integration with ralph-loop.sh:**
- New `ARCH_MODE=orchestrated` (alongside `serial` and `parallel`)
- When a phase boundary is reached, the loop runs the orchestrator agent instead of directly calling `run_parallel_phase`
- The orchestrator's JSON output is parsed by the bash loop, which then dispatches accordingly
- Falls back to plan-driven behavior if the orchestrator fails

**Files to modify:**
- `lib/exec.sh` — new `run_orchestrated_phase()` function
- `lib/detect.sh` — parse orchestrator JSON output
- `ralph-loop.sh` — new `ARCH_MODE=orchestrated` branch
- `.claude/agents/orchestrator.md` — new agent
- `templates/implementation-plan.md` — add `orchestrated` as Architecture option
- `prompt-plan.md` — document orchestrated mode

**Tools the orchestrator needs:**
- `read_file`, `write_file` (read plan, checkpoint, phase outputs)
- No web_search, no compilation — it's a decision-making agent, not a worker

## 2. Thread-Aware Pipeline Parallelism

**What:** Instead of phase gates (all scouts finish → all triagers start), each thematic thread flows through the pipeline independently.

**Example:**
```
Thread thermal:     scout → triage → deep-reader → critic    (ahead)
Thread structural:  scout → triage → (still running)
Thread deployment:  scout → (still running)
```

**How it works:**
- One worktree per thread (persists across the thread's pipeline stages)
- Each thread has its own checkpoint tracking which stage it's at
- A thread advances to its next stage as soon as its current stage completes
- Join points declared in the plan force threads to synchronize

**Plan format for threads:**
```markdown
## Phase 1: Research (thread-pipeline)

### Thread: thermal-management
- [ ] 1a. Scout thermal papers — **scout**
- [ ] 1b. Deep read thermal papers (depends: 1a) — **deep-reader**
- [ ] 1c. Critique thermal findings (depends: 1b) — **critic**

### Thread: structural-analysis
- [ ] 2a. Scout structural papers — **scout**
- [ ] 2b. Deep read structural papers (depends: 2a) — **deep-reader**
- [ ] 2c. Critique structural findings (depends: 2b) — **critic**

## Phase 2: Synthesis (join)
- [ ] 3. Synthesize all threads (depends: 1c, 2c) — **synthesizer**
```

**Implementation:**
- `detect_threads()` in `lib/detect.sh` — parses thread blocks from plan
- `run_thread_pipeline()` in `lib/exec.sh` — manages per-thread worktrees and advancement
- Thread state tracked in `checkpoint.md` with per-thread sections
- Join points detected from `(depends: ...)` that reference tasks across threads

**Requires:** The orchestrator agent (to decide when threads should synchronize, handle cross-thread dependencies, detect when a thread is stuck)

**Key design questions:**
- How to handle cross-thread resource discovery (scout-thermal finds paper relevant to structural)
- How to bound cost (N threads × M stages = N×M agent invocations)
- When to fall back to phase gates (non-threadable work, tightly coupled tasks)

## 3. Coarse Task Sub-Tasking

**What:** When a task is too large for one agent session, split it at runtime.

**When it matters:**
- "Deep read 50 papers" — too many for one context window
- "Write all sections" — should be split into per-section tasks
- "Review entire codebase" — needs batching

**How it works:**
- The orchestrator detects a coarse task (by reading the plan + checkpoint)
- It produces subtasks as an `adapt` action
- The bash loop inserts subtasks into the plan and dispatches them
- Subtask results are rolled up into the parent task's completion

**Implementation:**
- Orchestrator agent logic (no new bash functions needed)
- `lib/detect.sh` — handle subtask numbering (7a, 7b, 7c)
- Plan format supports sub-numbering

## 4. MCP Tools for Worktree Management

**What:** Expose worktree lifecycle as MCP tools so the orchestrator agent can manage isolation directly.

**Why:** Currently the bash loop creates/removes worktrees. If the orchestrator needs to make dynamic decisions ("spin up 3 worktrees for batch 1, wait, then 3 more for batch 2"), it needs to control worktree lifecycle itself.

**Tools:**
- `worktree_create` — creates a worktree for a given task, returns the path
- `worktree_list` — lists active worktrees and their branches
- `worktree_merge` — merges a worktree branch into main
- `worktree_remove` — cleans up a worktree

**Integration:**
- Add to `tools/worktree.py` (new module)
- Register in `tools/__init__.py` for the orchestrator agent
- The orchestrator's `.md` file declares these in its `## Tools` section

**NOT needed until:** The orchestrator agent is implemented and needs dynamic dispatch.

## 5. Richer Plan Format

**What:** Extend `implementation-plan.md` to express thread identity, dependency graphs, and parallelism budgets.

**New fields:**
```markdown
**Architecture:** orchestrated
**Parallel budget:** 6          <!-- max concurrent agents -->
**Thread strategy:** pipeline   <!-- pipeline | phase-gates | auto -->
```

**New task annotations:**
```markdown
- [ ] 1a. Scout thermal (thread: thermal) — **scout**
- [ ] 3. Synthesize (join: 1c, 2c) — **synthesizer**
- [ ] 7. Write paper (max-context: 200k) — **paper-writer**
```

**Plan agent changes:**
- `prompt-plan.md` — document new fields and annotations
- `.claude/agents/plan.md` — update parallelism reference
- Plan agent learns to assess whether work is threadable

## Implementation Priority

| Priority | Item | Depends on | Complexity |
|----------|------|------------|------------|
| 1 | Orchestrator agent | Nothing (builds on current worktree infra) | Medium |
| 2 | Richer plan format | Orchestrator (needs someone to read the new annotations) | Low |
| 3 | Coarse task sub-tasking | Orchestrator (it's the one that splits tasks) | Medium |
| 4 | Thread-aware pipelines | Orchestrator + richer plan format | High |
| 5 | MCP worktree tools | Orchestrator (only consumer) | Low |

Items 1-3 can be done incrementally. Item 4 is the most complex and should wait until 1-3 are proven.

## What we learned from integration testing

Bugs discovered during the JobSearch integration test that inform this design:

1. **Agents don't always commit their work.** The auto-commit safety net in `merge_worktree` is essential. Any future orchestrator design must assume agents are unreliable about git hygiene.

2. **Agents write prose in Next Task instead of task references.** The fallback-to-plan mechanism is essential. The orchestrator should own Next Task state rather than trusting agents to write it correctly.

3. **Shared files always conflict in parallel merges.** The "checkout --ours + reconcile separately" pattern is the right approach. Any new shared files (e.g., per-thread checkpoints) need the same treatment.

4. **Rate limiting with concurrent OAuth sessions.** The 2-second spawn stagger helps. The orchestrator's batching capability would handle this more intelligently.

5. **Stale branches from crashed runs.** The cleanup-before-create pattern in `create_worktree` is essential. The orchestrator should also be able to detect and clean up orphaned worktrees.
