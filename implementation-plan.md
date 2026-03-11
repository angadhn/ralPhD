# Implementation Plan — benchmarking-infra

**Thread:** benchmarking-infra
**Created:** 2026-03-11
**Autonomy:** autopilot

## Context

ralPhD runs 12 agents in serial relay (one agent per iteration). To benchmark
the multi-agent architecture, we need: (1) evaluation infrastructure to capture
metrics, (2) two additional execution modes — parallel fan-out and single-agent
— so we can compare all three on the same task, and (3) plan mode awareness of
parallelism annotations so plans encode which phases have independent agents.

The Architecture field in the plan (like the existing Autonomy field) tells
build mode how to execute. CLI flags on build mode can override for benchmarking.

## Design Decisions

1. **Architecture field in implementation-plan.md** — `**Architecture:** serial | parallel | auto`. Plan mode sets this based on task analysis. Build mode reads it. CLI flags (`--serial`, `--parallel`, `--single`) override for benchmarking.
2. **Parallel annotation syntax** — phase headings get `(parallel)` suffix: `## Phase 3 — Critical review (parallel)`. Build mode spawns concurrent `ralph_agent.py` processes for all unchecked tasks in that phase when in parallel mode.
3. **Single-agent mode** — `prompt-build-single.md` combines all agent capabilities into one prompt. Bypasses agent detection entirely. Same state files, same tools (full registry).
4. **Eval data goes to `logs/eval.jsonl`** — separate from `logs/usage.jsonl` (which tracks raw API usage). Eval captures higher-level metrics: productivity, quality gates, task completion.
5. **evaluate_run.py --compare** — reads eval.jsonl files from multiple runs, produces comparison table. Runs are tagged by architecture mode.

<!-- gate -->

## Phase 1 — Evaluation infrastructure

- [x] 1. Create `specs/evaluation-metrics.md` — define each metric (cost, productivity, quality gates, context efficiency, task completion), how it's collected, what "good" looks like — **coder**
- [x] 2. Create `scripts/evaluate_iteration.py` — runs after each iteration, captures: tokens in/out/cost (from usage.jsonl), files changed/lines added/removed (git diff), quality gate pass/fail (check_language, check_journal results), peak context %, task completion (checkpoint delta). Appends to `logs/eval.jsonl` — **coder**
- [x] 3. Create `scripts/evaluate_run.py` — aggregates eval.jsonl across a full run: total cost, iterations, wall-clock time, quality gate pass rate, cost per completed task, context utilization distribution. Supports `--compare mode1 mode2 mode3` to produce side-by-side comparison from tagged runs — **coder**
- [x] 4. Wire `evaluate_iteration.py` into `ralph-loop.sh` — call after each iteration, after usage logging. Tag each eval entry with the current architecture mode. ~5 lines — **coder**

<!-- gate -->

## Phase 2 — Architecture modes in build

- [x] 5. Add `--serial`, `--parallel`, `--single` flags to `ralph-loop.sh` — parse in arg loop, set `ARCH_MODE` variable, default to reading `**Architecture:**` field from implementation-plan.md. If field missing, default to `serial` — **coder**
- [x] 6. Implement parallel execution in `ralph-loop.sh` — when `ARCH_MODE=parallel` and current phase is marked `(parallel)`, collect all unchecked tasks in that phase, spawn one `ralph_agent.py` per task concurrently, wait for all to finish, then continue. Each parallel agent writes to its own output subdir. Handle: shared checkpoint conflicts (each agent updates its own task only), usage logging per agent, eval capture per agent — **coder**
- [x] 7. Create `prompt-build-single.md` — single combined prompt that includes all agent capabilities. Reads the same state files. Gets full tool registry (all 17 tools). No agent detection — runs as one iteration until task list is exhausted or context yields — **coder**
- [x] 8. Implement single-agent mode in `ralph-loop.sh` — when `ARCH_MODE=single`, use `prompt-build-single.md`, skip `detect_agent`, pass full tool registry. Still respects context yield and iteration limits — **coder**

<!-- gate -->

## Phase 3 — Plan mode parallelism awareness

- [ ] 9. Update `prompt-plan.md` — add step in plan generation where the planner analyzes agent dependencies and marks phases with independent agents as `(parallel)`. Add `**Architecture:**` field to plan header template. Planner sets it to `parallel` if any phases are annotatable, `serial` if all phases are strictly sequential — **coder**
- [ ] 10. Update `prompt-build.md` — add instruction to read `**Architecture:**` field and respect `(parallel)` phase annotations. Document that CLI flags override the plan field — **coder**

<!-- gate -->

## Phase 4 — Verification and documentation

- [ ] 11. Update tests in `tests/test-workflow-local.sh` — add tests for: Architecture field parsing, parallel phase detection, eval.jsonl output format, --serial/--parallel/--single flag parsing — **coder**
- [ ] 12. Update `README.md` — document benchmarking workflow: how to plan with annotations, run three modes, compare results. Include example commands for the IFP benchmarking run — **coder**
- [ ] 13. Add per-agent model config to `context-budgets.json` — add `model` field per agent (e.g., `"coder": {"model": "claude-sonnet-4-6", ...}`, `"critic": {"model": "claude-opus-4-6", ...}`). `ralph-loop.sh` reads model field for detected agent, passes to `ralph_agent.py --model`. Falls back to `CLAUDE_MODEL` env var if not set — **coder**

## Files Changed

| File | Action |
|------|--------|
| `specs/evaluation-metrics.md` | CREATE |
| `scripts/evaluate_iteration.py` | CREATE |
| `scripts/evaluate_run.py` | CREATE |
| `prompt-build-single.md` | CREATE |
| `ralph-loop.sh` | MODIFY (flags, parallel exec, single mode, eval hook) |
| `prompt-plan.md` | MODIFY (parallelism analysis step, Architecture field) |
| `prompt-build.md` | MODIFY (read Architecture field) |
| `tests/test-workflow-local.sh` | MODIFY (new tests) |
| `README.md` | MODIFY (benchmarking docs) |

| `context-budgets.json` | MODIFY (add per-agent model field) |
| `ralph_agent.py` | MODIFY (accept --model override from loop) |

**No changes to:** `tools/`, `.claude/agents/`, `specs/*-output-format.md`
