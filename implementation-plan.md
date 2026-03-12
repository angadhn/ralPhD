# Implementation Plan — orchestration-redesign

**Thread:** orchestration-redesign
**Created:** 2026-03-12
**Architecture:** serial

## Context

ralPhD's parallel mode is fundamentally broken: it parallelizes across roles (scout + reader + critic simultaneously) when the correct model is parallelism within a role (4 scouts simultaneously, then 6 readers simultaneously, etc.). The Howler research-companion codebase has a working orchestrator that gets this right. This thread's job is to design the new orchestration model for ralPhD.

Read `ai-generated-outputs/orchestration-redesign/brief.md` for the full problem statement, Howler reference architecture, and constraints.

Also read the Howler orchestrator source directly for design insight:
- `~/all-Claude-Code-projects/Howlerv2/supabase/functions/_shared/research-companion/prompts/orchestrator.ts`
- `~/all-Claude-Code-projects/Howlerv2/supabase/functions/_shared/research-companion/prompts/orchestrator-helpers.ts`
- `~/all-Claude-Code-projects/Howlerv2/supabase/functions/_shared/research-companion/constants.ts`
- `~/all-Claude-Code-projects/Howlerv2/supabase/functions/_shared/research-companion/types.ts`

And the current ralPhD orchestration code:
- `ralph-loop.sh`, `lib/exec.sh`, `lib/detect.sh`, `lib/config.sh`
- `prompt-build.md`, `prompt-build-single.md`
- `.claude/agents/*.md` (all agent prompts)

## Deliverable

A new implementation plan (written to `ai-generated-outputs/orchestration-redesign/`) that specifies:

1. **The orchestration model** — how `ralph-loop.sh` should decide what to run next, replacing the naive `(parallel)` phase annotation
2. **The plan format** — what an implementation-plan.md should look like to express pipeline stages and within-stage parallelism
3. **The dispatch mechanism** — how the loop spawns N agents of the same role with different assignments (different search angles, different paper batches, different sections)
4. **The dependency protocol** — how the loop knows when a stage is complete and the next stage can begin
5. **The file changes** — which files need to change and how (ralph-loop.sh, lib/exec.sh, lib/detect.sh, prompt-build.md, etc.)
6. **Benchmark compatibility** — how eval.jsonl and evaluate_run.py work with the new model

This is a **design task**, not an implementation task. The output is a detailed implementation plan, not code.

## Tasks

- [ ] 1. Read the Howler orchestrator source (orchestrator.ts, orchestrator-helpers.ts, constants.ts, types.ts) and extract the dispatch patterns that work — **deep-reader**
- [ ] 2. Read the current ralPhD orchestration code (ralph-loop.sh, lib/exec.sh, lib/detect.sh, lib/config.sh) and identify what needs to change — **deep-reader**
- [ ] 3. Read Yegge's GasTown multi-agent architecture (https://maggieappleton.com/gastown) and extract relevant patterns — how GasTown handles agent coordination, task decomposition, and parallel execution. Compare with Howler's approach and note what applies to ralPhD's constraints (filesystem-based communication, Claude Code sessions, no shared memory) — **deep-reader**
- [ ] 4. Read the GasTown source code (find the repo from the Maggie Appleton article or https://github.com/steveyegge/gastown) — focus on the orchestration layer: how agents are spawned, how tasks are assigned, how dependencies between agents are tracked, how results are collected. Write findings to ai-generated-outputs/orchestration-redesign/gastown-code-analysis.md — **deep-reader**
- [ ] 5. Read all ralPhD agent prompts (.claude/agents/*.md) and map the actual data dependencies between agents (who reads whose output) — **scout**
- [ ] 6. Design the new orchestration model: plan format, dispatch mechanism, dependency protocol — write to ai-generated-outputs/orchestration-redesign/design.md. Key question to answer: is an orchestrator agent only needed when the plan involves multi-agent parallelism? Serial single-agent execution (the current default) may work fine with the dumb dispatcher — the orchestrator might be a capability that activates only when the plan requires fan-out and dependency resolution — **synthesizer**
- [ ] 7. Write the detailed implementation plan with file-level change specs — write to ai-generated-outputs/orchestration-redesign/implementation-plan.md — **paper-writer**
- [ ] 8. Review the implementation plan for gaps, contradictions, and missing edge cases — **critic**

## Post-completion

Archive `ai-generated-outputs/orchestration-redesign/` once the design is accepted and implementation begins.
