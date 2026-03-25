# Ralph — Research Paper Loop

Autonomous loop for writing research papers. Claude reads papers, builds arguments, writes sections, checks compliance, and generates figures — one agent at a time, with human checkpoints built in.

Designed for PhD-level STEM work targeting peer-reviewed journals. All claims must be substantiated by peer-reviewed or conference papers.

## How it works

Each iteration of the loop:

1. Shell reads `prompt-build.md` (the dispatcher)
2. Claude studies `checkpoint.md` and `implementation-plan.md`, picks the highest-priority task
3. The last word in the task name is the agent (e.g., `scout`, `STYLE-CHECK critic`)
4. Claude reads that agent's file and follows its workflow
5. Agent produces outputs, updates `implementation-plan.md` and `checkpoint.md`, commits, and exits
6. Shell starts a fresh iteration with a new context window

The loop runs until you stop it (Ctrl+C twice) or it writes `HUMAN_REVIEW_NEEDED.md`.

## Prerequisites

- **Python ≥ 3.10** (3.13 recommended)
- **Claude CLI** — `npm install -g @anthropic-ai/claude-code` then `claude login`
- **jq** — `brew install jq` (macOS) or `apt install jq` (Linux)
- **Python deps** — `pip install -r requirements.txt` (installs `mcp` and `rich`)

The `mcp` package is required for headless mode without an API key (OAuth / Max plan). If you have `ANTHROPIC_API_KEY` set, `ralph_agent.py` handles everything and `mcp` is not needed.

## Getting started

```bash
git clone https://github.com/angadhn/ralPhD.git
cd ralPhD
pip install -r requirements.txt   # one-time setup
```

### A. Run from the ralPhD repo (simplest)

```bash
./ralph-loop.sh plan               # plan your research goal
./ralph-loop.sh                    # build — let the loop run
```

### B. Separate project workspace (recommended for multiple projects)

Each project gets its own workspace with its own git history, checkpoint, and outputs. You can run as many projects as you like against one ralPhD install. Each workspace has its own `papers/` directory — drop in the PDFs relevant to that project.

```bash
# First paper — solar energy review
~/ralPhD/scripts/init-project.sh ~/research/solar-review
cd ~/research/solar-review
cp ~/Downloads/solar-*.pdf papers/
./ralphd plan
./ralphd -p build

# Second paper — different topic, separate workspace and papers
~/ralPhD/scripts/init-project.sh ~/research/battery-modeling
cd ~/research/battery-modeling
cp ~/Downloads/battery-*.pdf papers/
./ralphd plan
```

The init script creates the directory, initializes a git repo (agents commit after every step), symlinks `specs/`, `templates/`, and `.claude/agents/` back to the framework, and generates a `./ralphd` launcher. The two workspaces are fully independent — different papers, different plans, different outputs.

### C. Brownfield (inside an existing project)

```bash
~/ralPhD/scripts/init-project.sh ~/my-existing-codebase/.ralph
cd ~/my-existing-codebase/.ralph
./ralphd plan
```

Creates an isolated `.ralph/` workspace inside your existing project, with its own git history so it doesn't pollute your project's commits. Agents can read parent code via `../`.

### D. Standalone (fully self-contained, no framework dependency)

```bash
~/ralPhD/scripts/init-project.sh ~/research/solar-review/.ralph --standalone
cd ~/research/solar-review/.ralph
./ralphd plan
```

Copies the entire engine into the workspace — zero symlinks, no RALPH_HOME needed at runtime. Content directories (`papers/`, `ai-generated-outputs/`, etc.) are created directly inside the workspace. Add project-specific agents to `.claude/agents/`. Useful when you want a portable, versionable workspace that doesn't depend on the original ralPhD checkout.

Plan mode produces `implementation-plan.md`. Build mode executes it.

See [Initialization modes](#initialization-modes) for details on what `init-project.sh` sets up.

## Initialization modes

`scripts/init-project.sh` has two orthogonal axes that control how a workspace is set up.

### Link strategy

| Mode | Flag | What happens |
|------|------|-------------|
| **Local** (default) | — | Symlinks `.claude/agents/`, `specs/`, and `templates/` to RALPH_HOME. Changes to the framework are immediately visible in all workspaces. |
| **Standalone** | `--standalone` | Copies the **full engine** (`ralph-loop.sh`, `lib/`, `tools/`, `ralph_agent.py`, prompts, config, specs, templates, agents) into the workspace. No symlinks, no RALPH_HOME dependency at runtime. Project-specific agents can be added directly to `.claude/agents/`. Includes launcher, git init, and brownfield detection. |
| **CI** | `--ci` | Copies specs, templates, and agents (like standalone) but skips the engine, launcher, and git init. For GitHub Actions where the workflow calls `ralph-loop.sh` directly via RALPH_HOME. |

### Layout

| Mode | When | What happens |
|------|------|-------------|
| **Split** | Workspace directory is named `.ralph` | Content directories (`papers/`, `corpus/`, `sections/`, etc.) live in the parent directory. Symlinks inside `.ralph/` point up to them (`../papers/`, etc.) so agents see everything via relative paths. |
| **All-in-one** | Any other directory name | Everything lives in one directory. No content symlinks needed. |

Layout is determined by the directory name you pass — there is no flag. If `basename` is `.ralph`, you get split layout; otherwise, all-in-one. Exception: `--standalone` and `--ci` always use all-in-one (content dirs inside the workspace) regardless of directory name.

```bash
# Split layout (workspace = .ralph subdirectory)
~/ralPhD/scripts/init-project.sh ~/my-project/.ralph

# All-in-one layout (workspace = the directory itself)
~/ralPhD/scripts/init-project.sh ~/my-workspace
```

### What gets symlinked (local mode)

| Symlink | Target | Purpose |
|---------|--------|---------|
| `.claude/agents/` | `RALPH_HOME/.claude/agents/` | Agent prompts (entire directory) |
| `specs/` | `RALPH_HOME/specs/` | Quality standards and output format specs |
| `templates/` | `RALPH_HOME/templates/` | Starter checkpoint and plan templates |
| `papers/`, `corpus/`, etc. (split layout only) | `../papers/`, `../corpus/`, etc. | Content directories in parent |

The `ralphd` launcher recreates broken symlinks on every run (self-healing).

### Agent symlink implication

Because `.claude/agents/` is symlinked as a whole directory, new agent files created during project runs land in RALPH_HOME, not in the project. This means:

- Useful agents organically flow back to the framework — every workspace benefits.
- Project-specific agents cannot be committed to the project's own git history.
- To make an agent project-local, you would need to break the symlink and copy the agents directory.

## Running the loop

```bash
./ralph-loop.sh              # interactive, build mode
./ralph-loop.sh plan         # interactive, plan mode (no -p)
./ralph-loop.sh -p           # headless (piped), build mode
./ralph-loop.sh -p 20        # headless, build mode, max 20 iterations
```

**Flags:**

| Flag | Default | Description |
|------|---------|-------------|
| `-p` | off | Headless mode — pipes prompt to agent runner, logs output |
| `plan` | — | Use plan-mode prompt instead of build |
| `build` | default | Build mode (explicit, same as no flag) |
| `N` | unlimited | Max iterations before stopping |
| `--serial` | — | Force serial architecture mode |
| `--parallel` | — | Force parallel architecture mode |

**Environment:**

| Variable | Default | Description |
|----------|---------|-------------|
| `RALPH_MODEL` | `claude-opus-4-6` | Which model to use (`claude-*` or `gpt-5.4`) |
| `CLAUDE_MODEL` | — | Alias for `RALPH_MODEL` (backward compatible) |
| `RALPH_HOME` | script directory | Path to the ralPhD framework repo |
| `ANTHROPIC_API_KEY` | — | Anthropic API key (for headless mode via `ralph_agent.py`; not needed for OAuth/Max plan users) |
| `OPENAI_API_KEY` | — | OpenAI API key (or use `codex login` — see auth below) |
| `RALPH_CONTEXT_WINDOW` | per-model | Context window override in tokens (e.g. `200000` to revert to 200k) |
| `RALPH_MCP_LOG` | — | Path to MCP server debug log (opt-in; e.g. `/tmp/ralph-mcp.log`) |

By default each agent uses the model specified in `context-budgets.json`. The current default config uses Opus for all listed agents. Setting `RALPH_MODEL` overrides this globally — all agents use that one model.

`context-budgets.json` currently uses three core fields:

- `model`: which model the agent runs on
- `effort`: provider-specific reasoning effort for models that support it
- `max_tokens`: maximum output tokens for one model response; Ralph defaults this to `32768` if not set

The richer monitor fields (`max_step`, `steps.read_inputs`, `steps.read_chunk`) are intentionally not set by default. They tune when the shell monitor recommends `CAUTION` or `YIELD`, so they should be added only after observing a real agent's context behavior rather than guessing.

**OpenAI model policy:** Only **GPT-5.4** (high thinking mode) is supported for OpenAI. Ralph automatically sets `reasoning_effort: "high"` for GPT-5.4 calls. Context window is 272k tokens.

**OpenAI auth:** Ralph auto-discovers credentials in this order: `OPENAI_API_KEY` env var → Codex CLI auth file (`~/.codex/auth.json`) → Codex CLI keychain entry. If you have Codex CLI installed, just run `codex login` and Ralph will pick up the token automatically — no env var needed.

**Interactive mode:** With Anthropic models, interactive mode uses the `claude` CLI (full TUI) for both plan and build modes. With OpenAI models, interactive mode uses `codex` CLI when installed (full TUI), otherwise falls back to `ralph_agent.py`. Headless mode (`-p`) uses `ralph_agent.py` when `ANTHROPIC_API_KEY` is set. Without an API key (OAuth / Max plan users), it falls back to `claude -p` with ralph's tools exposed via MCP server — no API key needed, just `claude login`.

### How the MCP fallback works

For headless Anthropic runs, Ralph has two different runtime paths:

- **API key present** — `ralph_agent.py` runs the model loop directly. It loads the selected agent prompt, registers that agent's allowed tools, sends tool results back to the model, and logs usage.
- **OAuth / Max plan (no API key)** — `claude -p` runs the model loop instead. Ralph still provides the same agent prompt and the same per-agent tool boundaries, but it does so through `tools/mcp_server.py`, which exposes only the tools assigned to that agent.

This means the *runtime substrate* differs, but the high-level agent design stays the same: Ralph binds an agent prompt to a model and a restricted tool surface. In other words, the MCP server is not "the agent"; it is the bridge that lets Claude CLI see only the tools that a given Ralph agent is supposed to use.

## Steering the loop

### checkpoint.md

This is the shared state between iterations. Every agent reads it and writes it back. The key field is **Next Task** — it controls which agent runs next.

### implementation-plan.md

The task list. Generated by plan mode or written by hand. Build mode studies this alongside `checkpoint.md` to pick the highest-priority task each iteration.

### inbox.md

Drop operator notes here from another terminal while the loop is running. The shell prepends them to the next iteration's prompt and clears the file. Useful for mid-run course corrections without stopping the loop.

### HUMAN_REVIEW_NEEDED.md

When an agent encounters something that needs human judgment, it writes this file and exits. The loop pauses and prints the contents. To resume: review, edit `checkpoint.md` if needed, delete the file, and restart. This is a runtime gate file and should not be committed.

### Reflections

Every 5th iteration, the loop triggers a reflection. Claude reads its recent progress (CHANGELOG + git log), asks whether the research direction is working, and records the assessment.

Full reflections go to `ai-generated-outputs/reflections/reflection-iter-N.md`. A summary line goes to `CHANGELOG.md` and `checkpoint.md`.

### Usage tracking

Every iteration logs token usage and cost to `logs/usage.jsonl`. In headless mode (`-p`), usage is written by `ralph_agent.py` to a machine-readable JSON file that `ralph-loop.sh` appends to the usage log. In interactive mode, usage is extracted from the Claude session JSONL file via `scripts/extract_session_usage.py`.

Run `python3 scripts/usage_report.py` to see a summary of token usage and costs across all iterations.

## Agents

Twelve agents, each handling one type of work per iteration:

| Agent | What it does |
|-------|-------------|
| **scout** | Searches literature, scores papers, builds a reading list |
| **triage** | Deduplicates corpus, resolves grade conflicts, generates reading plan |
| **deep-reader** | Reads papers in depth, extracts claims and data, maps sections |
| **critic** | Assesses structure; checks style, journal, figure compliance; proposes figures |
| **provocateur** | Stress-tests arguments: negative space, inverted assumptions, cross-domain bridges |
| **synthesizer** | Merges findings into synthesis narrative, master.bib, and section outline |
| **paper-writer** | Writes or revises paper sections; reviews editor changes |
| **editor** | Substantiated edits to .tex sections with evidence backing |
| **coherence-reviewer** | Post-editing QA: promise-delivery, terminology, contradictions, novelty claims |
| **research-coder** | Generates analysis scripts and figures |
| **figure-stylist** | Reviews figures for visual clarity and print readiness |
| **coder** | Reads, modifies, and tests application source code |

Agent files live in `.claude/agents/`. Each inherits shared protocol from `agent-base.md` and has its own inputs, outputs, workflow steps, and yield protocol. The dispatcher never needs to know the details — it just routes.

Typical flow:

```
scout → triage → deep-reader → critic → provocateur → synthesizer
  → paper-writer → editor → coherence-reviewer → research-coder → figure-stylist
```

When all tasks complete, the loop auto-compiles `main.tex` → `main.pdf` if present.

Some agents have modes. The mode is a prefix in the Next Task field:

```
scout              → literature search
GAP-FILL scout     → targeted gap-fill search
critic             → survey assessment
STYLE-CHECK critic → writing style review
JOURNAL-CHECK critic → journal compliance check
FIGURE-PROPOSAL critic → identify claims needing figures
REVIEW-EDITS paper-writer → accept/revert editor changes
```

The agent detects its mode from the prefix.

## Project structure

**Framework** (`$RALPH_HOME` — the ralPhD repo):

```
ralPhD/
├── ralph-loop.sh               # The loop (shell infrastructure)
├── lib/                        # Sourced shell helpers for the loop
│   ├── config.sh               # CLI parsing, env/bootstrap, architecture resolution
│   ├── detect.sh               # Next-task parsing, phase detection, task collection
│   ├── monitor.sh              # Context budgeting and heartbeat/status monitoring
│   ├── exec.sh                 # Model resolution and parallel execution helpers
│   └── post-run.sh             # Usage logging, eval capture, human-review gate, circuit breaker
├── ralph_agent.py              # Python agent runner for headless build mode
├── providers.py                # Provider abstraction (Anthropic + OpenAI)
├── prompt-build.md             # Build-mode dispatcher
├── prompt-plan.md              # Plan-mode dispatcher
├── context-budgets.json        # Per-agent context budget config
├── .claude/agents/             # 12 agent prompts + agent-base.md shared protocol
├── tools/                      # Tool registry + per-agent tool implementations
│   ├── __init__.py             # Merged registry, AGENT_TOOLS, dispatch
│   ├── core.py                 # read_file, write_file, bash, git_commit, git_push
│   ├── checks.py               # Compatibility shim over the check/citation modules
│   ├── check_language.py       # Language-quality checks
│   ├── check_journal.py        # Journal-compliance checks
│   ├── check_figure.py         # Figure-compliance checks
│   ├── citations.py            # citation_lint/lookup/verify/verify_all/manifest
│   ├── claims.py               # check_claims (cross-ref .tex + evidence-ledger + .bib)
│   ├── pdf.py                  # pdf_metadata, extract_figure
│   ├── download.py             # citation_download
│   ├── search.py               # list_files, code_search
│   ├── interact.py             # ask_choice, ask_question, scan_workspace (unused — plan uses claude CLI)
│   ├── mcp_server.py           # MCP server exposing per-agent tools (for claude -p fallback)
│   ├── cli.py                  # CLI dispatcher — invoke any tool from Bash
│   ├── redact.py               # Secret redaction + preview truncation
│   ├── fmt.py                  # Rich formatted output for headless mode
│   ├── github.py               # gh CLI wrapper (PRs, issues, releases)
│   └── latex.py                # compile_latex (pdflatex + bibtex build cycle)
├── scripts/                    # Utility scripts + project scaffolding
│   ├── init-project.sh         # Scaffold a new project workspace
│   ├── evaluate_iteration.py   # Post-iteration metric capture → eval.jsonl
│   └── evaluate_run.py         # Run aggregation + --compare mode
├── specs/                      # Quality standards + output format templates
└── templates/                  # Starter checkpoint.md + implementation-plan.md
```

**Workspace** (your project directory — CWD when running):

```
my-paper/
├── ralphd                      # Launcher (generated by init-project.sh)
├── .ralphrc                    # RALPH_HOME path
├── checkpoint.md               # Shared state between iterations
├── implementation-plan.md      # Task list (output of plan mode)
├── inbox.md                    # Operator notes (auto-cleared)
├── CHANGELOG.md                # Rolling progress log
├── iteration_count             # Persistent counter
├── specs -> $RALPH_HOME/specs  # Symlink (self-healing)
├── templates -> ...            # Symlink (self-healing)
├── papers/                     # Input PDFs
├── corpus/                     # Extracted text / processed papers
├── sections/                   # Draft paper sections
├── references/                 # BibTeX, citation data
├── figures/                    # Generated figures
├── logs/                       # Per-iteration usage (usage.jsonl)
├── archive/                    # Old plans and historical research
└── ai-generated-outputs/       # All agent outputs, organized by thread
```

When running from the ralPhD repo directly, framework and workspace files coexist in the same directory (backward compatible).

## Advanced usage

### RALPH_HOME

`RALPH_HOME` env var points to the ralPhD framework directory. All framework files (agents, tools, scripts, specs) are resolved relative to it. Project files (checkpoint, papers, outputs) stay in CWD.

Resolution order: `RALPH_HOME` env var > `.ralphrc` file (read by `./ralphd` launcher) > script directory (default, backward compatible).

**CI example** (GitHub Actions):

```yaml
steps:
  - uses: actions/checkout@v4                         # workspace repo
  - uses: actions/checkout@v4
    with: { repository: you/ralPhD, path: .ralph-engine }
  - run: RALPH_HOME=$GITHUB_WORKSPACE/.ralph-engine ./ralphd -p build 5
```

### GitHub Actions

The CI workflow (`ralph-run.yml`) has been removed. ralPhD now runs locally only via `./ralph-loop.sh` or `./ralphd`. For CI use, check out ralPhD as an engine and invoke it directly:

```yaml
steps:
  - uses: actions/checkout@v4                         # workspace repo
  - uses: actions/checkout@v4
    with: { repository: you/ralPhD, path: .ralph-engine }
  - run: RALPH_HOME=$GITHUB_WORKSPACE/.ralph-engine ./ralphd -p build 5
```

### Benchmarking

Ralph supports two architecture modes for execution.

#### Architecture modes

| Mode | What happens |
|------|-------------|
| **serial** (default) | One agent per iteration, sequential relay |
| **parallel** | Phases marked `(parallel)` in the plan run their tasks concurrently |

Set the mode via CLI flag or the `**Architecture:**` field in `implementation-plan.md`. CLI flags override the plan field.

```bash
./ralph-loop.sh -p --serial build 10    # serial relay (default)
./ralph-loop.sh -p --parallel build 10  # parallel fan-out on annotated phases
```

#### Plan annotations for parallelism

Plan mode (`./ralph-loop.sh plan`) analyzes agent dependencies and marks independent phases with `(parallel)`:

```markdown
## Phase 2 — Literature review (parallel)

- [ ] 3. Search ML databases — **scout**
- [ ] 4. Search neuroscience databases — **scout**
- [ ] 5. Search clinical databases — **scout**
```

The `**Architecture:**` field is set automatically:

```markdown
**Architecture:** parallel   # if any phases are annotatable
**Architecture:** serial     # if all phases are strictly sequential
```

#### Evaluation metrics

Each iteration appends metrics to `logs/eval.jsonl` via `scripts/evaluate_iteration.py`. Metrics cover five categories: cost (tokens, USD), productivity (files/lines changed), quality gates (language + journal checks), context efficiency (peak %, yield), and task completion.

After a run, aggregate and compare:

```bash
# Summary of a single run
python3 scripts/evaluate_run.py logs/eval.jsonl

# Compare two architecture modes
python3 scripts/evaluate_run.py --compare \
  logs/eval-serial.jsonl \
  logs/eval-parallel.jsonl
```

#### Running a benchmark comparison

```bash
# 1. Plan the task (sets Architecture field automatically)
./ralph-loop.sh plan

# 2. Run both modes on the same plan
cp logs/eval.jsonl logs/eval.jsonl.bak  # preserve any prior data

./ralph-loop.sh -p --serial build 20
cp logs/eval.jsonl logs/eval-serial.jsonl

git checkout -- checkpoint.md           # reset state
./ralph-loop.sh -p --parallel build 20
cp logs/eval.jsonl logs/eval-parallel.jsonl

# 3. Compare results
python3 scripts/evaluate_run.py --compare \
  logs/eval-serial.jsonl \
  logs/eval-parallel.jsonl
```

The comparison table shows total cost, iterations, wall-clock time, quality gate pass rate, cost per completed task, and context utilization for each mode.

### Tool registry

`ralph_agent.py` is a thin Python runner that replaces `claude -p` inside `ralph-loop.sh`. It gives each agent a curated tool set instead of Claude Code's full ~20+ built-in tools.

Tools are defined in `tools/` and registered per-agent in `tools/__init__.py`:

| Agent | Tools (beyond essentials) |
|-------|--------------------------|
| scout | pdf_metadata, citation_lookup/verify/verify_all, citation_manifest/download |
| triage | pdf_metadata, citation_verify_all |
| deep-reader | pdf_metadata, extract_figure |
| critic | check_language, check_journal, check_figure, check_claims, citation_verify_all |
| provocateur | (essentials only) |
| synthesizer | citation_lint, citation_verify_all |
| paper-writer | check_language, citation_lint, compile_latex |
| editor | check_claims, check_language, citation_lint, citation_verify_all |
| coherence-reviewer | check_claims, check_language |
| research-coder | (essentials only) |
| figure-stylist | check_figure |
| coder | bash, gh |

Every agent gets 6 essentials: `read_file`, `write_file`, `git_commit`, `git_push`, `list_files`, `code_search`. 20 tools total, with `tools/checks.py` kept as a compatibility shim over the split check modules.

Based on [ghuntley's agent architecture](https://ghuntley.com/agent): the agent = the loop + tool registry, the prompt = behavioral guidance.

## Design decisions

- **Research-first, not spec-first.** The loop starts from questions, not specifications. The plan evolves as understanding deepens.
- **No orchestrator agent.** `checkpoint.md` and `implementation-plan.md` are the shared state. The dispatcher is ~25 lines. Claude picks the highest-priority task each iteration.
- **One agent per iteration.** Each iteration gets a fresh context window. No agent mixing, no subagent spawning.
- **Per-agent tool registries.** Each agent only sees the tools it needs. Scout gets citation tools, critic gets compliance checkers, research-coder gets only the essentials. This focuses the model's attention and prevents tool misuse. Tool registries are enforced on both the `ralph_agent.py` path (API key present) and the MCP fallback path (`claude -p` + `mcp_server.py`, for OAuth/Max plan users without an API key); plan mode and interactive CLI mode (`claude`/`codex`) use provider-native tools.
- **Plan mode records missing capabilities rather than creating agents.** If a task needs a capability that doesn't exist yet, plan mode writes a scoped follow-up task instead of editing `.claude/agents/*` directly.
- **Peer-reviewed sources only.** Scout searches academic databases via `tools/_citation.py`. No general web search — journal submissions cite peer-reviewed and conference papers.
- **Human in the loop.** `HUMAN CHECKPOINT` tasks pause for review. `inbox.md` allows mid-run steering. Reflections every 5 iterations surface drift.

## References

- [ghuntley/how-to-ralph-wiggum](https://github.com/ghuntley/how-to-ralph-wiggum) — minimal loop, flat files, plan/build split
- [frankbria/ralph-claude-code](https://github.com/frankbria/ralph-claude-code) — .ralph/ directory, circuit breakers, status block parsing, .ralphrc config
