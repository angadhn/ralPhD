# Implementation Plan — Fix init-project path resolution and symlink fragility

**Thread:** fix-init-paths
**Created:** 2026-03-13
**Architecture:** serial
**Autonomy:** stage-gates

## Context

`init-project.sh` uses `PROJECT_ROOT="$(pwd)"` instead of deriving it from the workspace argument. When a user runs Quick Start B (`~/ralPhD/scripts/init-project.sh ~/research/my-paper`) from an arbitrary directory, content directories (`papers/`, `corpus/`, `figures/`, etc.) are created in cwd — not in the project. Relative `../` symlinks inside the workspace then point to wrong locations.

Additionally, `.claude/agents/` is never symlinked or populated in local mode, so Claude Code (and users) can't discover agents in new workspaces. The `ralphd` launcher has no self-healing for `.claude/agents`. And `ralph-loop.sh` reads `checkpoint.md` and `implementation-plan.md` via relative paths from cwd, which may not be the workspace directory.

## Full audit findings

A repo-wide audit identified **100+ relative path references** across shell scripts, Python tools, agent prompts, and CI workflows. However, all of them share one root assumption: **cwd = workspace directory**. Rather than rewriting every path, we fix the three entry points that establish cwd:

1. **`init-project.sh`** — derives `PROJECT_ROOT` from `$(pwd)` instead of from the WORKSPACE argument, scattering content dirs into the wrong location.
2. **`ralphd` launcher** — does not `cd` into its own directory before exec'ing `ralph-loop.sh`, so cwd may not be the workspace.
3. **`.claude/agents/`** — never symlinked in local mode, invisible to Claude Code.

Once these three are fixed, all downstream relative paths (`ralph-loop.sh`, `lib/*.sh`, `scripts/archive.sh`, `tools/*.py`, agent prompts) resolve correctly because cwd will be the workspace.

### Files with relative-path cwd assumptions (for reference, no changes needed)

| File | Key relative paths | Fixed by launcher `cd` |
|------|---|---|
| `ralph-loop.sh` | `checkpoint.md`, `implementation-plan.md`, `iteration_count`, `inbox.md`, `logs/` | Yes |
| `lib/post-run.sh` | `HUMAN_REVIEW_NEEDED.md`, `CHANGELOG.md` (6 instances) | Yes |
| `lib/monitor.sh` | `AI-generated-outputs/$thread` + nested agent paths (8 instances) | Yes |
| `scripts/archive.sh` | `checkpoint.md`, `implementation-plan.md`, `archive/`, `ai-generated-outputs/`, `CHANGELOG.md`, `inbox.md`, `logs/usage.jsonl`, `iteration_count` (16 instances) | Yes |
| `tools/citations.py` | `corpus/batch_results.jsonl`, `papers/` | Yes |
| `tools/pdf.py` | `figures/` default output dir | Yes |
| `tools/download.py` | `papers` default dir | Yes |
| `tools/check_journal.py` | `Path("references")` | Yes |
| `tools/interact.py` | `checkpoint.md`, `implementation-plan.md`, `human-inputs/`, `corpus/`, `papers/`, `.tex`/`.bib` globs (12 instances) | Yes |
| `prompt-build.md` | `checkpoint.md`, `implementation-plan.md` | Yes |
| `prompt-plan.md` | `checkpoint.md`, `implementation-plan.md` | Yes |
| All agent `.md` files | `checkpoint.md`, `sections/`, `papers/`, `corpus/`, `AI-generated-outputs/`, etc. (30+ instances) | Yes |
| `.github/workflows/ralph-run.yml` | Uses `cd workspace` pattern — consistent, no change needed | N/A (CI mode) |

## Bugs identified

1. **`PROJECT_ROOT="$(pwd)"` scatters content dirs into cwd** — should derive from WORKSPACE parent (or WORKSPACE itself for same-dir mode)
2. **`.claude/agents/` empty in local mode** — never symlinked to RALPH_HOME
3. **No self-healing for `.claude/agents/`** in the ralphd launcher
4. **`ralphd` launcher doesn't `cd` into workspace** — all downstream relative paths break when invoked from project root
5. **`.ralphrc` bakes an absolute `RALPH_HOME` path at init time** — breaks if the ralPhD repo moves
6. **Content symlink self-healing guards on `basename = .ralph`** — fails for any other workspace name
7. **`[ ! -e "$link" ]` doesn't catch dangling symlinks** — broken symlinks still "exist" as links, so re-init skips them

## Design Decisions

1. **Derive `PROJECT_ROOT` from `WORKSPACE`** — for Quick Start B (`init-project.sh ~/research/my-paper`), `PROJECT_ROOT = WORKSPACE`. For Quick Start C (`init-project.sh ~/Howlerv2/.ralph`), `PROJECT_ROOT = parent of WORKSPACE`. Heuristic: if WORKSPACE basename is `.ralph`, split layout; otherwise, all-in-one.
2. **Symlink `.claude/agents/` to RALPH_HOME in local mode** — same pattern as `specs/` and `templates/`
3. **`ralphd` launcher should `cd` into its own directory** before exec'ing `ralph-loop.sh` — this fixes all relative path assumptions downstream without touching any other file
4. **Use `-L` test for dangling symlink detection** — `[ -L "$link" ] && [ ! -e "$link" ]` catches dangling links; `[ ! -e "$link" ]` alone does not
5. **Remove `basename = .ralph` guard** in launcher self-healing — heal content symlinks whenever WORKSPACE ≠ PROJECT_ROOT, regardless of directory name

<!-- gate -->

## Phase 1 — Fix PROJECT_ROOT derivation in init-project.sh

- [x] 1. Replace `PROJECT_ROOT="$(pwd)"` with logic that derives PROJECT_ROOT from WORKSPACE: if basename is `.ralph`, PROJECT_ROOT = parent; otherwise PROJECT_ROOT = WORKSPACE. Fix dangling symlink detection in content symlink creation (line 75) to use `[ -L "$link" ] || [ ! -e "$link" ]` pattern. Add test that runs `init-project.sh /tmp/test-project` from `/tmp` and verifies content dirs are in `/tmp/test-project/`, not `/tmp/` — **coder**

<!-- gate -->

## Phase 2 — Symlink .claude/agents in local mode

- [x] 2. In init-project.sh local-mode branch (the `else` at line 133), replace `mkdir -p "$WORKSPACE/.claude/agents"` with a symlink to `$RALPH_HOME/.claude/agents`, matching the pattern used for `specs/` and `templates/` (recreate if target changed, skip if regular dir exists). Add self-healing for `.claude/agents` in the embedded ralphd launcher alongside the existing specs/templates healing — **coder**

<!-- gate -->

## Phase 3 — Fix ralphd launcher cwd and self-healing

- [x] 3. Add `cd "$SCRIPT_DIR"` to the ralphd launcher before `exec ralph-loop.sh` so that all relative paths in ralph-loop.sh resolve against the workspace directory. Remove the `basename = .ralph` guard from content symlink self-healing so it works for any workspace directory name — **coder**

<!-- gate -->

## Phase 4 — Update README and api-contract layout docs

- [x] 4. Update Quick Start B in README.md to clarify that content dirs are created inside the workspace (not cwd). Update the directory tree in `specs/api-contract.md` to reflect that split layout only applies to brownfield `.ralph/` case (Quick Start C), not Quick Start B. Verify Quick Start A (run from ralPhD repo) is unaffected — **coder**

<!-- gate -->

## Phase 5 — Test all three quick-start paths

- [ ] 5. Add test cases to `tests/test-workflow-local.sh` covering: (a) Quick Start A — run from ralPhD repo, (b) Quick Start B — `init-project.sh /tmp/test-qs-b` run from a different directory, verify content dirs + symlinks + `.claude/agents` are all inside `/tmp/test-qs-b/`, (c) Quick Start C — `init-project.sh /tmp/test-qs-c/.ralph` run from `/tmp/test-qs-c`, verify content at project root, framework state in `.ralph/`, symlinks resolve. Each test: init, verify dirs exist, verify symlinks resolve, verify `ralphd` is executable and `--help` works — **coder**

## Files Changed

| File | Action |
|------|--------|
| `scripts/init-project.sh` | MODIFY (phases 1, 2, 3) |
| `README.md` | MODIFY (phase 4) |
| `specs/api-contract.md` | MODIFY (phase 4) |
| `tests/test-workflow-local.sh` | MODIFY (phase 5) |

**No changes to:** `ralph-loop.sh`, `ralph_agent.py`, `lib/*.sh`, `tools/`, `.claude/agents/`, `.github/workflows/`
