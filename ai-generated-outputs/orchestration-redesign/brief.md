# Orchestration Redesign Brief

## Problem

ralPhD's current parallel mode (`--parallel`) parallelizes across **roles** within a plan phase — e.g., running scout + deep-reader + critic simultaneously. This is broken because these agents have strict data dependencies: reader needs scout's output, critic needs reader's output. The pipeline is inherently sequential across roles.

## What actually works (from Howler's research-companion)

The Howler codebase at `~/all-Claude-Code-projects/Howlerv2/supabase/functions/_shared/research-companion/` has a production orchestrator that gets this right. Key files:

- `prompts/orchestrator.ts` — 5-phase orchestrator (plan → confirm → build → blocked → done)
- `prompts/orchestrator-helpers.ts` — decision rules, batch sizing, checkpoint management
- `constants.ts` — `WORKER_AGENT_TYPES`, `TOKEN_BUDGET`, `RESEARCH_FUNNEL` targets
- `types.ts` — `SharedContext` interface showing what gets passed between agents

### How Howler parallelizes correctly

1. **Same-role parallelism**: 4 scouts with different search angles in parallel, 3 peer reviewers in parallel, 4 section editors (intro/methods/results/discussion) in parallel
2. **Pipeline ordering via orchestrator decision logic** — the orchestrator's build prompt has explicit rules:
   - "If scouts just returned → spawn triage or deep readers"
   - "If deep readers returned → spawn critic + provocateur + synthesizer"
   - "If synthesis returned → spawn paper_writer or section editors"
3. **Adaptive batch sizing** — `floor((120K - 15K overhead) / avg_tokens_per_paper)`, clamped to [3, 10]
4. **The plan is a task list, not an execution schedule** — the orchestrator reads uncompleted tasks and decides the right next action based on what's available

### The correct mental model

```
Phase 1: 4× scout (parallel, different search angles)
          ↓ all finish
Phase 2: triage (serial — one agent scores all candidates)
          ↓
Phase 3: 6× deep-reader (parallel, different paper batches)
          ↓ all finish
Phase 4: critic + provocateur (parallel — both read the same corpus)
          ↓ all finish
Phase 5: synthesizer (serial — needs all analysis)
          ↓
Phase 6: 4× section-writer (parallel, different sections)
          ↓ all finish
Phase 7: coherence-reviewer (serial — reads all sections)
```

Parallelism is **horizontal** (same role, multiple topics/batches), never **vertical** (different roles on the same data).

## What exists in ralPhD today

- `ralph-loop.sh` — main loop, dispatches one agent per iteration (serial) or all tasks in a `(parallel)` phase
- `lib/exec.sh` — `run_parallel_phase()` spawns concurrent `ralph_agent.py` processes
- `lib/detect.sh` — `detect_current_phase()`, `is_parallel_phase()`, `collect_phase_tasks()`
- `lib/config.sh` — `resolve_arch_mode_from_plan()`, CLI flags `--serial`/`--parallel`/`--single`
- `prompt-build.md` — dispatcher prompt for serial build mode
- `prompt-build-single.md` — single-agent mode prompt
- `context-budgets.json` — per-agent model + context config

The current `(parallel)` annotation on phases is the wrong abstraction. It just means "run everything in this phase at once" with no understanding of dependencies.

## Constraints

- **Agents are Claude Code sessions** — each `ralph_agent.py` invocation is a separate process with its own context window
- **Communication is via filesystem** — agents read/write to shared directories (corpus/, papers/, sections/, etc.)
- **No shared memory** — agents can't talk to each other mid-execution; orchestration happens between iterations
- **The split layout** — content dirs at project root, framework state in `.ralph/`; symlinks make both views work
- **Existing agent prompts** (`.claude/agents/*.md`) should need minimal changes
- **`ralph-loop.sh` is the loop** — it runs iterations, the question is how it decides what to run next
- **Benchmarking still matters** — eval.jsonl captures per-iteration metrics; the new design must support comparing serial vs orchestrated runs
