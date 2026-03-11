# Implementation Plan — ralph-home-separation

**Thread:** ralph-home-separation
**Created:** 2026-03-11

## Goal

Separate ralPhD into a reusable engine + lightweight per-project workspaces. Introduce `RALPH_HOME` env var so the framework stays in one repo while projects live in their own directories. Backward compatible — running from the ralPhD repo itself still works (RALPH_HOME defaults to script directory).

## Why

- Copying the entire repo for each project causes framework files to drift out of sync
- Framework updates (bug fixes, new agents, new tools) must be manually re-copied
- Doesn't work for brownfield projects (e.g. Howlerv2) where ralPhD needs to coexist with an existing codebase

## Design

**Core idea:** `RALPH_HOME` env var points to the ralPhD repo. CWD is the project workspace. Framework lookups use `$RALPH_HOME/`, project I/O uses CWD.

**Framework files** (live in `$RALPH_HOME/`): `ralph_agent.py`, `ralph-loop.sh`, `prompt-build.md`, `prompt-plan.md`, `context-budgets.json`, `.claude/agents/`, `tools/`, `scripts/`, `specs/`, `templates/`

**Project files** (live in CWD): `checkpoint.md`, `implementation-plan.md`, `iteration_count`, `inbox.md`, `CHANGELOG.md`, `HUMAN_REVIEW_NEEDED.md`, `logs/usage.jsonl`, `papers/`, `corpus/`, `sections/`, `references/`, `figures/`, `ai-generated-outputs/`

**`scripts/init-project.sh`** scaffolds a new workspace: creates dirs, symlinks `specs/` and `templates/`, copies initial state, generates a thin `ralph` launcher that sets `RALPH_HOME` and execs `ralph-loop.sh`.

## Tasks

- [x] 1. Add RALPH_HOME resolution to `ralph-loop.sh`: after mode-parsing (line 16), resolve `RALPH_HOME` defaulting to script dir, validate it contains `ralph_agent.py`, then prefix 7 framework file references — `PROMPT_FILE` (lines 7/12/13), `context-budgets.json` (line 171), agent file check (line 318), `ralph_agent.py` invocation (line 362), `extract_session_usage.py` (line 480). Project files (`checkpoint.md`, `implementation-plan.md`, `iteration_count`, `inbox.md`, `CHANGELOG.md`, `logs/`) stay CWD-relative. Export `RALPH_HOME` so child processes inherit it. — **research-coder**

- [x] 2. Update `ralph_agent.py` to resolve agent prompts and `context-budgets.json` via RALPH_HOME: change agent path (line 266) to use `os.environ.get("RALPH_HOME", str(Path(__file__).parent))`, same for `budgets_path` (line 255). `.env` loading and `from tools import ...` already use `Path(__file__).parent` / Python import resolution — no change needed there. — **research-coder**

- [x] 3. Add `_scripts_dir()` helper to `tools/checks.py`, `tools/pdf.py`, and `tools/download.py` — resolves `scripts/` path via `RALPH_HOME` env var, falling back to `Path(__file__).parent.parent / "scripts"`. Replace all hardcoded `"scripts/..."` subprocess paths: 10 occurrences in `checks.py` (check_language, check_journal, check_figure, citation_tools.py x7), 3 in `pdf.py` (pdf_metadata, extract_figure x2), 1 in `download.py` (citation_tools.py manifest-add). — **research-coder**

- [x] 4. Update `scripts/archive.sh` to resolve template paths via RALPH_HOME: add `RALPH_HOME="${RALPH_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"` at top, change lines 62-63 from `cp templates/checkpoint.md` to `cp "$RALPH_HOME/templates/checkpoint.md"` (and same for implementation-plan.md). The `cd "$REPO_ROOT"` on line 12 should stay — archive operates on the workspace CWD, but templates come from the framework. — **research-coder**

- [x] 5. Create `scripts/init-project.sh` (~50 lines) — scaffolds a new project workspace. Creates directories (`ai-generated-outputs/`, `papers/`, `corpus/`, `sections/`, `references/`, `figures/`, `logs/`, `archive/`). Symlinks read-only framework dirs (`specs -> $RALPH_HOME/specs`, `templates -> $RALPH_HOME/templates`). Copies initial state from templates (`checkpoint.md`, `implementation-plan.md`). Creates `inbox.md` and `iteration_count` (0). Generates a thin `ralph` launcher script that sets RALPH_HOME and execs ralph-loop.sh (passing all args). Writes `.ralphrc` with RALPH_HOME path for reference. Should validate RALPH_HOME points to a valid ralPhD install before proceeding. — **research-coder**

- [x] 6. Update `README.md` — replace "Quick start" section with three usage modes: (a) running from the ralPhD repo (unchanged), (b) running in a separate project workspace via `init-project.sh`, (c) running inside an existing project (brownfield via `.ralph/` subdir). Update the "Structure" tree to distinguish framework vs workspace files. Add short section explaining `RALPH_HOME` and `scripts/init-project.sh`. Keep it concise — this is a README, not a tutorial. — **research-coder**

- [x] 7. Backward compatibility verification — from the ralPhD repo dir, verify: `./ralph-loop.sh plan` still works (RALPH_HOME defaults to script dir), `python3 ralph_agent.py --agent scout --task "test" --max-tokens 100` finds agent prompt and tools, all `scripts/` references resolve correctly. Fix any regressions. Do NOT actually launch a full agent session — just verify path resolution and error-free startup (e.g. dry-run or quick sanity check that files are found). — **research-coder**

- [x] 8. New-project smoke test — run `scripts/init-project.sh /tmp/ralph-test-workspace`, verify the directory structure is created, symlinks point correctly, `ralph` launcher script exists and has correct RALPH_HOME, `checkpoint.md` and `implementation-plan.md` are copied from templates. Clean up `/tmp/ralph-test-workspace` after. — **research-coder**

## Key design decisions

**Why RALPH_HOME, not pip install?** This is scripts + prompts, not a library. 2-3 users. pip is overengineering.

**Why not symlinks only?** Agents call git — git sees through symlinks and would commit in the wrong repo.

**Why not a `--project` flag?** The loop relies on CWD for git ops. Changing CWD mid-script is error-prone. Better to `cd` to workspace and run.

**Why symlink specs/ instead of copying?** Specs are framework standards (grading rubric, writing style). Agent prompts reference them by relative path from CWD. Symlinks keep them in sync across all workspaces. Per-project overrides: replace the symlink with a local `specs/` directory.

**Why export RALPH_HOME?** Child processes (ralph_agent.py, tools/*.py, scripts/*.sh) all need it. Exporting once in ralph-loop.sh avoids passing it through every invocation.
