# Evaluation Metrics — Benchmarking Infrastructure

> Defines the metrics collected by `evaluate_iteration.py` and `evaluate_run.py`
> to compare serial, parallel, and single-agent architecture modes.

## Overview

Each iteration appends one JSON object to `logs/eval.jsonl`. Run-level
aggregation reads the full file and produces summary statistics.
Metrics fall into five categories: cost, productivity, quality gates,
context efficiency, and task completion.

---

## 1. Cost

### 1a. Iteration Cost (`cost_usd`)

- **What:** Total API cost for one iteration (one agent invocation).
- **How collected:** Read from `logs/usage.jsonl` — the entry matching the
  current iteration number. Uses the `cost_usd` field if present; otherwise
  estimates from token counts using the pricing table in `usage_report.py`.
- **Unit:** USD (float, 4 decimal places).
- **Good:** < $3.00 per iteration for Opus. < $0.50 for Sonnet.

### 1b. Input Tokens (`input_tokens`)

- **What:** Total input tokens consumed (prompt + context).
- **How collected:** From `logs/usage.jsonl` entry for the iteration.
- **Unit:** Integer token count.
- **Good:** < 150k (leaves headroom in default 200k context window). Set `RALPH_CONTEXT_WINDOW=1000000` for 1M plans.

### 1c. Output Tokens (`output_tokens`)

- **What:** Total output tokens generated.
- **How collected:** From `logs/usage.jsonl` entry for the iteration.
- **Unit:** Integer token count.
- **Good:** Varies by agent. Paper-writer: 5k–15k. Scout: 2k–8k.

### 1d. Run Total Cost (`run_cost_usd`)

- **What:** Sum of all iteration costs across an entire run.
- **How collected:** `evaluate_run.py` sums `cost_usd` across all entries
  in `logs/eval.jsonl` for a given run tag.
- **Unit:** USD.
- **Good:** Depends on task complexity. Benchmark comparison is relative:
  lower is better at equal task completion.

### 1e. Cost Per Completed Task (`cost_per_task`)

- **What:** `run_cost_usd / tasks_completed`.
- **How collected:** Computed by `evaluate_run.py` at run end.
- **Unit:** USD per task.
- **Good:** The primary efficiency metric. Lower is better. Compare across
  architecture modes on the same task set.

---

## 2. Productivity

### 2a. Files Changed (`files_changed`)

- **What:** Number of files modified, added, or deleted in the iteration.
- **How collected:** `git diff --name-only HEAD~1` after the iteration commits.
  Excludes `checkpoint.md`, `implementation-plan.md`, `CHANGELOG.md`, and
  files under `AI-generated-outputs/` and `logs/`.
- **Unit:** Integer count.
- **Good:** > 0 (the iteration did something). Context-dependent beyond that.

### 2b. Lines Added (`lines_added`)

- **What:** Total lines added across all changed files.
- **How collected:** `git diff --numstat HEAD~1` — sum of column 1.
  Same exclusions as 2a.
- **Unit:** Integer count.
- **Good:** Agent-dependent. Coder: 20–200. Writer: 50–500.

### 2c. Lines Removed (`lines_removed`)

- **What:** Total lines removed across all changed files.
- **How collected:** `git diff --numstat HEAD~1` — sum of column 2.
  Same exclusions as 2a.
- **Unit:** Integer count.
- **Good:** Non-zero when refactoring or editing. Not inherently good or bad.

### 2d. Wall-Clock Duration (`duration_ms`)

- **What:** Elapsed time for the iteration from agent start to exit.
- **How collected:** From `logs/usage.jsonl` entry `duration_ms` field.
- **Unit:** Milliseconds.
- **Good:** < 300,000 ms (5 min) for most agents. Parallel mode should
  reduce total run wall-clock time even if per-iteration time is similar.

### 2e. Run Wall-Clock Time (`run_duration_ms`)

- **What:** Total elapsed time from first iteration start to last iteration end.
- **How collected:** `evaluate_run.py` computes from first and last timestamps
  in `logs/eval.jsonl`.
- **Unit:** Milliseconds.
- **Good:** Parallel < serial for runs with independent phases.

---

## 3. Quality Gates

### 3a. Language Check Pass (`language_check_pass`)

- **What:** Whether `check_language.py` passes on the current LaTeX output.
- **How collected:** Run `python3 scripts/check_language.py` after the iteration.
  Record boolean pass/fail and the count of flagged issues.
- **Unit:** Boolean + integer issue count.
- **Good:** `true` with 0 issues. Regressions (new issues introduced) are bad.

### 3b. Journal Check Pass (`journal_check_pass`)

- **What:** Whether `check_journal_compliance.py` passes.
- **How collected:** Run `python3 scripts/check_journal_compliance.py` after the
  iteration. Record boolean pass/fail and issue count.
- **Unit:** Boolean + integer issue count.
- **Good:** `true` with 0 issues.

### 3c. Quality Gate Pass Rate (`quality_pass_rate`)

- **What:** Fraction of iterations where all quality gates passed.
- **How collected:** `evaluate_run.py` computes
  `count(all gates pass) / total_iterations`.
- **Unit:** Float 0.0–1.0.
- **Good:** > 0.9. Quality should not degrade when switching architecture modes.

---

## 4. Context Efficiency

### 4a. Peak Context Percentage (`peak_context_pct`)

- **What:** Highest context window utilization observed during the iteration.
- **How collected:** Read from `/tmp/ralph-context-pct` at iteration end,
  or from the budget info file's `context_pct` field. Falls back to
  estimating from `input_tokens / context_window * 100` (context window
  is model-aware: 200k for Claude/o3/o4-mini, 128k for GPT-4o; override via `RALPH_CONTEXT_WINDOW`).
- **Unit:** Integer percentage (0–100).
- **Good:** < 55 (below yield threshold). Iterations that hit the yield
  threshold (55%) may have been truncated.

### 4b. Context Yield Triggered (`context_yield`)

- **What:** Whether the context yield mechanism fired during the iteration.
- **How collected:** Check if `/tmp/ralph-yield` existed when the iteration
  ended, or if `checkpoint.md` contains yield-related notes.
- **Unit:** Boolean.
- **Good:** `false`. Frequent yields indicate the agent is consuming too
  much context per iteration.

### 4c. Context Utilization Distribution (`context_distribution`)

- **What:** Histogram of peak context percentages across all iterations in a run.
- **How collected:** `evaluate_run.py` bins `peak_context_pct` values into
  buckets: 0–20%, 20–40%, 40–55%, 55%+.
- **Unit:** Array of counts per bucket.
- **Good:** Most iterations in the 20–40% bucket. Few or none in 55%+.

---

## 5. Task Completion

### 5a. Task Completed (`task_completed`)

- **What:** Whether the iteration's assigned task was marked done.
- **How collected:** Compare `checkpoint.md` before and after the iteration.
  A task is completed if it moves from `[ ]` to `[x]` in
  `implementation-plan.md`, or if the Knowledge State table gains a new
  "done" entry.
- **Unit:** Boolean.
- **Good:** `true`. Iterations that don't complete their task cost money
  without progress.

### 5b. Tasks Completed Per Run (`tasks_completed`)

- **What:** Total tasks checked off during the run.
- **How collected:** `evaluate_run.py` counts `[x]` entries in the final
  `implementation-plan.md`, or sums `task_completed` booleans from eval.jsonl.
- **Unit:** Integer count.
- **Good:** Equal to total tasks in the plan (all tasks done).

### 5c. Iterations Per Task (`iterations_per_task`)

- **What:** `total_iterations / tasks_completed`.
- **How collected:** Computed by `evaluate_run.py`.
- **Unit:** Float ratio.
- **Good:** Close to 1.0. Values > 2.0 indicate frequent retries or
  context yields splitting tasks across iterations.

---

## eval.jsonl Entry Format

Each iteration appends one JSON line:

```json
{
  "timestamp": "2026-03-11T15:00:00Z",
  "run_tag": "serial-run-1",
  "arch_mode": "serial",
  "iteration": 5,
  "agent": "coder",
  "thread": "benchmarking-infra",
  "cost_usd": 2.50,
  "input_tokens": 149168,
  "output_tokens": 3491,
  "duration_ms": 97814,
  "files_changed": 3,
  "lines_added": 142,
  "lines_removed": 8,
  "language_check_pass": true,
  "language_check_issues": 0,
  "journal_check_pass": true,
  "journal_check_issues": 0,
  "peak_context_pct": 38,
  "context_yield": false,
  "task_completed": true,
  "task_name": "Create specs/evaluation-metrics.md"
}
```

## Run Summary Format (evaluate_run.py output)

```
=== Run Summary: serial-run-1 (serial) ===
Iterations:          12
Tasks completed:     10/12
Wall-clock time:     42m 18s
Total cost:          $31.42
Cost per task:       $3.14
Quality pass rate:   0.92
Iterations per task: 1.20
Context distribution: [0-20%: 2, 20-40%: 7, 40-55%: 2, 55%+: 1]
```

## Comparison Table Format (evaluate_run.py --compare)

```
| Metric              | serial-run-1 | parallel-run-1 | single-run-1 |
|---------------------|-------------|----------------|-------------|
| Iterations          | 12          | 8              | 3           |
| Tasks completed     | 10          | 10             | 10          |
| Wall-clock time     | 42m 18s     | 22m 05s        | 38m 12s     |
| Total cost          | $31.42      | $28.15         | $45.80      |
| Cost per task       | $3.14       | $2.82          | $4.58       |
| Quality pass rate   | 0.92        | 0.88           | 0.70        |
| Iters per task      | 1.20        | 0.80           | 0.30        |
| Avg context %       | 35%         | 32%            | 48%         |
| Context yields      | 1           | 0              | 2           |
```
