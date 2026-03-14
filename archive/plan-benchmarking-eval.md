# Benchmarking & Evaluation Plan (Sections 0-4)

Archived from planning session for the next thread.

---

## 0. Post-E2E Calibration (prerequisite for accurate Section 1 metrics)

**Why before Section 1:** Section 1a captures "Context efficiency: peak context
% before yield." The yield signal is driven by `estimate_input_cost()` and
`compute_budget_info()` in `ralph-loop.sh`, which use constants that were
improved in commit `2feca33` but still need empirical validation against real
usage data.

**Depends on:** At least one full e2e run through `ralph-loop.sh -p` that
generates `logs/usage.jsonl` with 5+ entries per agent.

### 0a. Calibrate bytes-per-token ratio

Read `logs/usage.jsonl`. For each agent, compare file sizes read (from git
diff or tool call logs) against `input_tokens` reported by the API. Derive
actual bytes-per-token ratio for English markdown/LaTeX. Current default: 3.5.
Update `BYTES_PER_TOKEN` in `estimate_input_cost()` if the empirical value
differs by >10%.

### 0b. Calibrate baseline overhead per agent

From `logs/usage.jsonl`, take the first turn of each iteration (before any
tool results are appended). The `input_tokens` on that turn = system prompt +
tool schemas + task prompt. Subtract an estimate for the task prompt
(~`wc -c < prompt-build.md` / 3.5) to isolate system overhead per agent.
Current default: 3000 tokens. Update `BASELINE_OVERHEAD` if needed, or make
it per-agent in `context-budgets.json`.

### 0c. Validate yield timing

Compare the context % at which agents actually yielded (from eval data or
stderr logs) against the `CONTEXT_THRESHOLD` (50% for ≤200k, 65% for 1M). If agents are yielding
too early (leaving >30% unused) or too late (exhausting context), adjust
`CONTEXT_THRESHOLD` or per-agent `max_step` values.

**Files to modify:** `ralph-loop.sh` (constants), possibly `context-budgets.json`
**Data needed:** `logs/usage.jsonl` with 5+ entries per agent

---

## 1. Evaluation & Benchmarking Infrastructure

**Why first:** The Anthropic role's core ask is "design rigorous quantitative
evaluations." This is ralPhD's biggest gap. Without metrics, every other
improvement is un-measurable.

### 1a. Create `scripts/evaluate_iteration.py`

Runs after each iteration. Captures structured metrics:
- **Cost:** tokens in/out, cache hits, dollar cost (already in usage.jsonl)
- **Productivity:** files changed, lines added/removed (from git diff)
- **Quality gates:** pass/fail from check_language, check_journal, etc.
- **Context efficiency:** peak context % before yield
- **Task completion:** did the agent finish its assigned task? (parse checkpoint delta)

Output: append to `logs/eval.jsonl` — one JSON line per iteration with all metrics.

### 1b. Create `scripts/evaluate_run.py`

Aggregates `eval.jsonl` across a full run (all iterations for one thread).
Produces a summary report:
- Total cost, iterations, wall-clock time
- Quality gate pass rate over time
- Cost per completed task
- Context utilization distribution

### 1c. Wire into `ralph-loop.sh`

After each iteration (where usage is already logged), also run
`evaluate_iteration.py`. Minimal change — follows the existing pattern of
post-iteration hooks.

### 1d. Create `specs/evaluation-metrics.md`

Documents what each metric means, how it's collected, and what "good" looks
like. This is the spec that makes the benchmarking rigorous rather than ad-hoc.

**Files to create:** `scripts/evaluate_iteration.py`, `scripts/evaluate_run.py`,
`specs/evaluation-metrics.md`
**Files to modify:** `ralph-loop.sh` (add eval hook, ~3 lines)

---

## 2. Single-Agent Comparison Mode

**Why second:** This is the highest-signal demonstration of agent architecture
evaluation. "We believe multi-agent relay works better — here's the data."

### 2a. Create `prompt-build-single.md`

A single combined prompt that includes all agent capabilities (scout + reader +
critic + writer + coder + stylist). Same state files, same scripts, same
checkpoint relay. The only difference: one prompt instead of six agent files.

### 2b. Add `--single-agent` flag to `ralph-loop.sh`

When set, use `prompt-build-single.md` instead of `prompt-build.md`. Everything
else stays the same: context resets, checkpoint relay, usage logging, eval hooks.

### 2c. Run comparative benchmarks

Same research task, same model, two modes. The eval infrastructure from (1)
produces directly comparable metrics. Document results in a comparison report.

**Files to create:** `prompt-build-single.md`
**Files to modify:** `ralph-loop.sh` (add flag, ~10 lines)

---

## 3. Evidence Provenance System

**Why third:** Adds a **memory system** (long-term structured knowledge) — a key
competency for the role. Also mechanically enforces the "substantiated claims"
requirement that's currently only in prose.

### 3a. Create `specs/evidence-format.md`

Defines claim-evidence pairs in JSONL:
```json
{"claim": "...", "source_key": "bibtex_key", "source_section": "S3.2",
 "extraction_type": "direct_quote|paraphrase|inference",
 "confidence": "high|medium|low", "reviewer": "deep-reader"}
```

Stored in `ai-generated-outputs/<thread>/evidence-ledger.jsonl`.

### 3b. Create `scripts/check_provenance.py`

Reads draft + ledger. Flags:
- Claims without ledger entries
- Low-confidence inferences
- Stale entries (source not in current bibliography)

Follows existing `check_language.py` patterns (exit codes, stdout format).

### 3c. Update agent prompts

- `deep-reader.md`: append to evidence ledger after claim extraction
- `paper-writer.md`: run check_provenance before writing
- `critic.md`: add EVIDENCE-CHECK mode

**Files to create:** `specs/evidence-format.md`, `scripts/check_provenance.py`
**Files to modify:** `.claude/agents/deep-reader.md`, `.claude/agents/paper-writer.md`,
`.claude/agents/critic.md`

---

## 4. Context Compaction

**Why fourth:** Directly demonstrates **context compression** — called out
explicitly in the role description. Solves the real problem of state files
growing unboundedly across iterations.

### 4a. Add compaction trigger to `ralph-loop.sh`

Every 10th iteration (configurable via `COMPACT_INTERVAL`), check line counts
of checkpoint.md and implementation-plan.md. If either exceeds `MAX_STATE_LINES`
(default 200), run a compaction iteration before the next regular one.

### 4b. Create `prompt-compact.md`

A short dispatcher (~15 lines) that instructs Claude to: read both state files,
preserve actionable information (open tasks, current status, key decisions),
remove completed items and stale notes, write compacted versions back.

Follows the existing pattern of `prompt-plan.md` / `prompt-build.md`.

**Files to create:** `prompt-compact.md`
**Files to modify:** `ralph-loop.sh` (add compaction check, ~15 lines)
