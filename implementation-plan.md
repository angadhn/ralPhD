# Implementation Plan — ralph-as-engine

**Thread:** ralph-as-engine
**Created:** 2026-03-11
**Autonomy:** stage-gates

## Context

Howler v2's research companion duplicates ralPhD's agent roster in TypeScript edge functions. Instead of maintaining two harnesses, Howler should invoke ralPhD's `ralph-loop.sh` via GitHub Actions on connected repos. ralPhD becomes the single source of truth for research agent behavior. This plan covers the ralPhD side — making it invocable as a reusable engine from external triggers (GitHub Actions).

## Phase 0 — Archive hygiene

- [x] 1. Update `scripts/archive.sh` to archive all per-thread files that accumulate during a thread (e.g. `ai-generated-outputs/reflections/`, `inbox.md` content, any other files that currently persist stale after archiving) — **coder**
- [x] 2. Audit for other files that should be reset/archived on thread completion but currently aren't — check `logs/`, `ai-generated-outputs/`, and root-level `.md` files — **coder**

--- STAGE GATE: review archive changes before proceeding ---

## Phase 1 — GitHub Actions workflow for ralph-loop

- [x] 3. Create `.github/workflows/ralph-run.yml` — a `workflow_dispatch` action that accepts inputs (thread name, task prompt, autonomy level), checks out the target project repo, clones ralPhD as `RALPH_HOME`, and runs `ralph-loop.sh` — **coder**
- [x] 4. Add a `.ralph` init step to the workflow — if the target repo lacks `checkpoint.md` / `implementation-plan.md`, copy templates from `RALPH_HOME/templates/` — **coder**
- [x] 5. Test workflow locally with `act` or a test repo — verify ralph-loop.sh runs, agents load, tools execute, and outputs are committed back — **coder**

--- STAGE GATE: review workflow before proceeding ---

## Phase 2 — RALPH_HOME separation hardening

- [x] 6. Audit `ralph-loop.sh` for any remaining hardcoded paths that assume ralPhD is the project root (vs. RALPH_HOME pointing to the framework while CWD is the project) — **coder**
- [x] 7. Audit all agent prompts for path assumptions — ensure `specs/`, `templates/`, `tools/` references resolve via RALPH_HOME, while `checkpoint.md`, `implementation-plan.md`, `AI-generated-outputs/` resolve relative to CWD (the project) — **coder**
- [x] 8. Audit `ralph_agent.py` and `tools/__init__.py` — ensure tool paths (scripts, checks) resolve from RALPH_HOME — **coder**

--- STAGE GATE: review separation before proceeding ---

## Phase 3 — Result delivery

- [ ] 9. Add a post-run step to the workflow that commits AI-generated outputs back to the project repo (on a branch or directly, configurable) — **coder**
- [ ] 10. Add an optional webhook/callback step that posts a summary back to a URL (for Howler to pick up results and display in chat) — **coder**
- [ ] 11. Document the workflow_dispatch API contract — inputs, outputs, expected repo structure — so Howler's edge functions can trigger it — **coder**

--- STAGE GATE: review delivery mechanism before proceeding ---

## Phase 4 — Verification

- [ ] 12. End-to-end test: trigger the workflow from a test repo, verify ralph-loop runs, agents execute, outputs are committed, and summary is available — **coder**
- [ ] 13. Update README and agents README to document the new 12-agent system and GitHub Actions invocation — **coder**

## Tasks

13 tasks across 5 phases. All assigned to **coder** agent.
