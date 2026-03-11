# Stage Gate: Phase 5 → Phase 6

## What was completed

**Phase 5: Venue Convention + Housekeeping** (Tasks 17–18)

- **Task 17:** Updated `scripts/init-project.sh` to create `inputs/` directory during project init. Added a comment documenting the convention and a `README.md` inside `inputs/` with a usage table (reviewer feedback, prior submissions, venue guidelines, style files, supplementary notes). Idempotent — re-running init preserves existing files.

- **Task 18:** Updated `.claude/agents/README.md` from 6 agents to 11, with a tools column, typical pipeline flow diagram, and `inputs/` convention documentation. New agents: triage, provocateur, synthesizer, editor, coherence-reviewer.

**Overall progress:** 18 of 21 tasks complete. Phases 1–5 done.

## What the next phase will do

**Phase 6: Prompt Audit** (Task 19)

Audit all 11 agent prompts in `.claude/agents/*.md` against prompt quality guidelines:
1. Remove role-playing language ("You are an expert X" → state the task directly)
2. Convert negative prompts ("Don't do X" → positive instructions)
3. Compress sections that can be shorter without losing meaning
4. Verify mechanical procedures live in tools/specs, not baked into prompts
5. Report token cost of each prompt

This will modify every `.claude/agents/*.md` file. Changes should be semantic-preserving (same behavior, better prompting).

## Decision needed

Approve proceeding with prompt audit of all 11 agent files?
